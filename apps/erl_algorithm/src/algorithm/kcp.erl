%%%-------------------------------------------------------------------
%%% @author 100621
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(kcp).

-behaviour(gen_server).

%%/**
%% * 引用：https://blog.csdn.net/lixiaowei16/article/details/90485157
%% * 		http://vearne.cc/archives/39317
%% * 		https://github.com/shaoyuan1943/gokcp/blob/master/kcp.go
%% *		https://github.com/xtaci/kcp-go
%% *
%% * 0               4   5   6       8 (BYTE)
%% * +---------------+---+---+-------+
%% * |     conv      |cmd|frg|  wnd  |
%% * +---------------+---+---+-------+   8
%% * |     ts        |     sn        |
%% * +---------------+---------------+  16
%% * |     una       |     len       |
%% * +---------------+---------------+  24
%% * |                               |
%% * |        DATA (optional)        |
%% * |                               |
%% * +-------------------------------+
%% * conv:连接号。UDP是无连接的，conv用于表示来自于哪个客户端。对连接的一种替代, 因为有conv, 所以KCP也是支持多路复用的
%% * cmd:命令类型，只有四种:
%% * 				CMD四种类型
%% *                     ----------------------------------------------------------------------------------
%% * 					   |cmd 			|作用 					|备注                    				|
%% *                     ----------------------------------------------------------------------------------
%% * 					   |IKCP_CMD_PUSH 	|数据推送命令            |与IKCP_CMD_ACK对应      				|
%% *                     ----------------------------------------------------------------------------------
%% * 					   |IKCP_CMD_ACK 	|确认命令                |1、RTO更新，2、确认发送包接收方已接收到	|
%% *                     ----------------------------------------------------------------------------------
%% * 					   |IKCP_CMD_WASK 	|接收窗口大小询问命令     |与IKCP_CMD_WINS对应      				|
%% *                     ----------------------------------------------------------------------------------
%% * 					   |IKCP_CMD_WINS 	|接收窗口大小告知命令     |                        				|
%% *                     ----------------------------------------------------------------------------------
%% * frg:分片，用户数据可能会被分成多个KCP包，发送出去
%% * wnd:接收窗口大小，发送方的发送窗口不能超过接收方给出的数值
%% * ts: 时间序列
%% * sn: 序列号
%% * una:下一个可接收的序列号。其实就是确认号，收到sn=10的包，una为11
%% * len:数据长度(DATA的长度)
%% * data:用户数据
%% *
%% * KCP流程说明
%% * 1. 判定是消息模式还是流模式
%% * 		1.1 消息模式(不拆包): 对应传输--文本消息
%% * 			KCP header        KCP DATA
%% *       -----------------------------------------------------------------------------------------------------------------------
%% *       |  sn  |  90  |  --------------------  |  sn  |  91  |  --------------------  |  sn  |  92  |  --------------------   |
%% *       |  frg |  0   |  |       MSG1       |  |  frg |  0   |  |       MSG2       |  |  frg |  0   |  |       MSG3       |   |
%% *       |  len |  15  |  --------------------  |  sn  |  20  |  --------------------  |  sn  |  18  |  --------------------   |
%% *       -----------------------------------------------------------------------------------------------------------------------
%% * 		1.2 消息模式(拆包；拆包原则：根据MTU(最大传输单元决定))：对应传输--图片或文件消息
%% * 			KCP header        KCP DATA
%% *       -----------------------------------------------------------------------------------------------------------------------
%% *       |  sn  |  90  |  --------------------  |  sn  |  91  |  --------------------  |  sn  |  92  |  --------------------   |
%% *       |  frg |  2   |  |      MSG4-1      |  |  frg |  1   |  |      MSG4-2      |  |  frg |  0   |  |      MSG4-3      |   |
%% *       |  len | 1376 |  --------------------  |  sn  | 1376 |  --------------------  |  sn  |  500 |  --------------------   |
%% *       -----------------------------------------------------------------------------------------------------------------------
%% * 		Msg被拆成了3部分，包含在3个KCP包中。注意, frg的序号是从大到小的，一直到0为止。这样接收端收到KCP包时，只有拿到frg为0的包，才会进行组装并交付给上层应用程序。
%% *         由于frg在header中占1个字节，也就是最大能支持（1400 – 24[所有头的长度]） * 256 / 1024 = 344kB的消息
%% * 		1.3 流模式
%% * 			KCP header        KCP DATA
%% *       ---------------------------------------------------------------------------------
%% *       |  sn  |  90  |  -------  ------  --------  |  sn  |  91  |  --------------------
%% *       |  frg |  0   |  | MSG1| | MSG2| | MSG3-1|  |  frg |  0   |  |       MSG3-2     |
%% *       |  len | 1376 |  ------  ------  ---------  |  sn  |  53  |  --------------------
%% *       ---------------------------------------------------------------------------------
%% *      1.4 消息模式与流模式对比
%% * 			1.4.1 消息模式：	减少了上层应用拆分数据流的麻烦，但是对网络的利用率较低。Payload(有效载荷)少，KCP头占比过大。
%% * 			1.4.2 流模式：	KCP试图让每个KCP包尽可能装满。一个KCP包中可能包含多个消息。但是上层应用需要自己来判断每个消息的边界。
%% * 2. 根据不同模式，得到需要传输的数据片段(segment)
%% * 3. 数据片段在发送端会存储在snd_queue中
%% * -----------------进入发送、传输、接收阶段------------------------------------------------------------------
%% * 		-------------------------									-------------------------
%% * 		|	Sender				|									|	Receiver			|
%% * 		|		 ------------	|									|		 ------------	|
%% *		|		|	APP		|	|									|		|	APP		|	|
%% *		|		------------	|									|		------------	|
%% *		|		    \|/		|										|		    /|\			|
%% * 		|		------------	|									|		------------	|
%% *		|		|  send buf	|---|--------------- LINK --------------|----->	|receive buf|	|
%% *		|		------------	|									|		------------	|
%% * 		-------------------------									-------------------------
%% * 		此过程中的三个阶段分别对应一个容量(发送阶段：IKCP_WND_SND，传输阶段：cwnd，接受阶段：IKCP_WND_RCV)
%% * 		cwnd剩余容量：snd_nxt(计划要发送的下一个segment号)-snd_una(接受端已经确认的最大连续接受号)=LINK中途在传输的数据量
%% * 4. 需要发送的时候，会将数据转移到snd_buf；但是snd_buf大小是有限的，所以在转移之前需要判定snd_buf的大小
%% *		4.1 snd_buf未满：将snd_queue的数据块flush到snd_buf，知道snd_queue清空或snd_buf已满停止
%% * 		4.2 snd_buf已满、cwnd未满: 将snd_buf的数据send出去，然后将snd_queue写入snd_buf
%% * 		4.3 snd_buf已满、cwnd已满: 不在写入，通过一个定时器定时判断cwnd是否有剩余流量，如果存在，完成第二步操作
%% * 		4.4 其他情况：
%% * 			4.4.1 如果snd_queue已满，snd_buf已满，cwnd已满，数据依然会直接flush，如果失败，即算超时处理
%% *			4.4.2 如果NoDelay=false，就不在写入snd_buf
%% * 5. LINK: 回调UDP的send进行传输(kcp->output=udp_output)
%% * 6. 接受数据:
%% * 		6.1 数据发送给接受端，接受端通过input进行接受，并解包receive buf，有确认的数据包recv_buf-->recv_queue
%% *		6.2 获取完整用户数据：从receive queue中进行拼装完整用户数据
%% */

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
-define(IF(_CONDITION, _DO), ?IF(_CONDITION, _DO, ok)).
-define(IF(_CONDITION, _DO, _ELSE), case _CONDITION of true -> _DO; else -> _ELSE end).

-define(CURRENT, erlang:system_time(millisecond) - persistent_term:get(current)).

-define(IKCP_RTO_NDL, 30).
-define(IKCP_RTO_MIN, 100).
-define(IKCP_RTO_DEF, 200).
-define(IKCP_RTO_MAX, 60000).
-define(IKCP_CMD_PUSH, 81).
-define(IKCP_CMD_ACK, 82).
-define(IKCP_CMD_WASK, 83).
-define(IKCP_CMD_WINS, 84).
-define(IKCP_ASK_SEND, 1).
-define(IKCP_ASK_TELL, 2).
-define(IKCP_WND_SND, 32).
-define(IKCP_WND_RCV, 32).
-define(IKCP_MTU_DEF, 1400).
-define(IKCP_ACK_FAST, 3).
-define(IKCP_INTERVAL, 100).
-define(IKCP_OVERHEAD, 24).
-define(IKCP_DEADLINK, 20).
-define(IKCP_THRESH_INIT, 2).
-define(IKCP_THRESH_MIN, 2).
-define(IKCP_PROBE_INIT, 7000).
-define(IKCP_PROBE_LIMIT, 120000).
-define(IKCP_SN_OFFSET, 12).


-record(kcp, {
    %% conv:客户端来源id； mtu：最大传输单元(默认1400)；mss: 最大片段尺寸MTU-OVERHEAD；state: 连接状态（0xFFFFFFFF表示断开连接）
    conv = 0,mtu = ?IKCP_MTU_DEF,mss = ?IKCP_MTU_DEF - ?IKCP_OVERHEAD,state = 0
    %% snd_una: 第一个未确认的包; snd_nxt：下一个要发送的sn; rcv_nxt：下一个应该接受的sn
    ,snd_una = 0,snd_nxt = 0,rcv_nxt = 0
    %% 拥塞窗口阈值
    ,ssthresh = ?IKCP_THRESH_INIT
    %% RTT的平均偏差; RTT的一个加权RTT平均值，平滑值; RTT: 一个报文段发送出去，到收到对应确认包的时间差。
    ,rx_rttvar = 0,rx_srtt = 0
    %% 由ack接收延迟计算出来的重传超时时间(重传超时时间)，最小重传超时时间
    ,rx_rto = ?IKCP_RTO_DEF,rx_minrto = ?IKCP_RTO_MIN
    %% 发送窗口；接收窗口；远程窗口(发送端获取的接受端尺寸)；拥塞窗口大小(传输窗口)；探查变量
    ,snd_wnd = ?IKCP_WND_SND,rcv_wnd = ?IKCP_WND_RCV,rmt_wnd = ?IKCP_WND_RCV,cwnd = 0,probe = 0
    %% 内部flush刷新间隔;  下次flush刷新时间戳
    ,interval = ?IKCP_INTERVAL,ts_flush = ?IKCP_INTERVAL
    %% 是否启动无延迟模式：0不需要，1需要；updated: 是否调用过update函数的标识
    ,nodelay = 0,updated = 0
    %% 窗口探查时间，窗口探查时间间隔
    ,ts_probe = 0,probe_wait = 0
    %% 最大重传次数; 可发送的最大数据量
    ,dead_link = ?IKCP_DEADLINK,incr = 0
    %% 重传
    ,fastresend = 0
    %% 取消拥塞控制，是否是流模式
    ,nocwnd = 0, stream = 0
    %% 发送队列; 发送buf; 接收队列; 接收buf
    ,snd_queue = [], rcv_queue = [], snd_buf = [], rcv_buf = []
    %% 待发送的ack列表(包含sn与ts)  |sn0|ts0|sn1|ts1|... 形式存在
    ,acklist = []
    %% 存储消息字节流的内存
    ,buffer = <<>>
    %% 不同协议保留位数
    ,reserved = 0
    %% 回调函数
    ,output
}).

-record(segment, {
    conv = 0
    ,cmd = 0
    ,frg = 0  %% 分片
    ,wnd = 0
    ,ts = 0
    ,sn = 0
    ,una = 0
    ,rto = 0
    ,xmit = 0
    ,resendts = 0
    ,fastack = 0
    ,acked = 0
    ,data = <<>>
}).

-record(ack_item, {
    sn = 0
    ,ts = 0
}).

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
    {ok, #kcp{}}.

handle_call(_Request, _From, State = #kcp{}) ->
    {reply, ok, State}.

handle_cast({recv, Buffer}, Kcp) ->
    try

        {noreply, Kcp}
    catch
        throw:_ ->
            {noreply, Kcp}
    end;
handle_cast(_Request, State = #kcp{}) ->
    {noreply, State}.

handle_info(_Info, State = #kcp{}) ->
    {noreply, State}.

terminate(_Reason, _State = #kcp{}) ->
    ok.

code_change(_OldVsn, State = #kcp{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%======================================================================================================================
%% Send
%%======================================================================================================================
%%// Send is user/upper level send, returns below zero for error
%%// 3. Send 数据格式化--> Segment
%%// * 1. 先判断消息类型；如果是流模式，则判断是否与现有Segment合并
%%// * 2. 如果是消息模式，则创建新Segment
send(Kcp, <<>>) -> %% 如果数据为空，直接退出
    {Kcp, -1}.
send(Kcp, Buffer) ->
    %% append to previous segment in streaming mode (if possible)
    %% 如果是流模式，则判断是否与现有Segment合并
    SndQueueReverse = lists:reverse(Kcp#kcp.snd_queue),
    case Kcp#kcp.stream of
        0 ->
            {SndQueueReverse, Buffer};
        _ ->
            N = erlang:length(SndQueueReverse),
            {SndQueueReverse1, Buffer1} =
                case N > 0 of
                    true ->
                        [Seg | SndQueueReverseO] = SndQueueReverse,
                        DataLen = erlang:byte_size(Seg#segment.data),
                        BufferLen = erlang:byte_size(Buffer),
                        case DataLen < Kcp#kcp.mss of
                            true ->
                                Capacity = Kcp#kcp.mss - DataLen,
                                Extend = ?IF(BufferLen < Capacity, BufferLen, Capacity),

                                <<Add2Seg:Extend, OtherBuffer/bytes>> = Buffer,
                                {[Seg#segment{data = <<(Seg#segment.data)/bytes, Add2Seg/bytes>>} | SndQueueReverseO], OtherBuffer};
                            _ ->
                                {SndQueueReverse, Buffer}
                        end;
                    _ ->
                        {SndQueueReverse, Buffer}
                end,
            case erlang:byte_size(Buffer1) of
                0 ->
                    %% return 0
                    {Kcp, 0};
                BufferLen1 ->
                    Count =
                        case BufferLen1 =< Kcp#kcp.mss of
                            true ->
                                1;
                            _ ->
                                (BufferLen1 + Kcp#kcp.mss - 1) div Kcp#kcp.mss
                        end,
                    case Count > 255 of
                        %% return 2
                        true -> {Kcp, -2};
                        _ ->
                            Count1 = ?IF(Count == 0, 1, Count),
                            loop_seg(0, Count1, BufferLen1, Buffer1, Kcp, SndQueueReverse1),
                            {Kcp#kcp{snd_queue = lists:reverse(SndQueueReverse1)}, 0}
                    end
            end
    end.

loop_seg(I, Count, _BufferLen, Buffer, _Kcp, SndQueueReverse) when I + 1 >= Count ->
    {Buffer, SndQueueReverse};
loop_seg(I, Count, BufferLen, Buffer, Kcp, SndQueueReverse) ->
    Size  = min(BufferLen, Kcp#kcp.mss),
    %% init seg
    %% todo
    Seg = #segment{},
    <<Add:Size, OtherBuffer/bytes>> = Buffer,
    Seg1 = Seg#segment{
        data = Add
        ,frg = ?IF(Kcp#kcp.stream == 0, Count - I - 1, 0)
    },
    SndQueueReverse1 = [Seg1 | SndQueueReverse],
    loop_seg(I + 1, Count, BufferLen - Size, OtherBuffer, Kcp, SndQueueReverse1).
%%======================================================================================================================




%%======================================================================================================================
%% Flush
%%======================================================================================================================
%%/**
%% * 4. 需要发送的时候，会将数据转移到snd_buf；但是snd_buf大小是有限的，所以在转移之前需要判定snd_buf的大小
%% * ackOnly=true  更新acklist(待发送列表)
%% * ackOnly=false 更新acklist(待发送列表), 将snd_queue移动到snd_buf，确认重传数据及时间
%% * 通过kcp.output:发送数据
%% */
flush(Kcp, AckOnly) ->
    Seg = #segment{
        conv = Kcp#kcp.conv
        ,cmd = ?IKCP_CMD_ACK
        ,wnd = wnd_unused(Kcp)
        ,una = Kcp#kcp.rcv_nxt
    },
    Mtu = Kcp#kcp.mtu,
    {_, Ptr1} = flush_acknowledges([], Kcp, Seg, <<>>),
    Kcp1 = Kcp#kcp{acklist = []},

    %% 仅仅更新acklist
    case AckOnly of
        true ->
            flush_buffer(Ptr1), %% flash remain ack segments
            {Kcp1, Kcp1#kcp.interval};
        _ ->
            %% probe window size (if remote window size equals zero)
            Kcp2 =
                case Kcp1#kcp.rmt_wnd == 0 of %% 如果远程端口尺寸==0
                    true ->
                        Current = ?CURRENT,
                        case Kcp1#kcp.probe_wait == 0 of %% 如果探查等待时间也没有设定
                            true ->
                                Kcp1#kcp{
                                    probe_wait = ?IKCP_PROBE_INIT   %% 则7s后进行窗口尺寸探查
                                    ,ts_probe = Current + Kcp1#kcp.probe_wait   %% 探查时间为当前时间+7s
                                };
                            _ ->
                                case Current - Kcp1#kcp.ts_probe >= 0 of    %% 判断当前时间已经到达窗口探查时间
                                    true ->
                                        Kcp11 = ?IF(Kcp1#kcp.probe_wait < ?IKCP_PROBE_INIT, Kcp1#kcp{probe_wait = ?IKCP_PROBE_INIT}, Kcp1),
                                        Kcp12 = Kcp11#kcp{probe_wait = Kcp11#kcp.probe_wait + Kcp11#kcp.probe_wait div 2}, %% 探查时间扩充一半
                                        Kcp13 = ?IF(Kcp12#kcp.probe_wait > ?IKCP_PROBE_LIMIT, Kcp12#kcp{probe_wait = ?IKCP_PROBE_LIMIT}, Kcp12), %% 如果新的扩充时间大于120s
                                        Kcp13#kcp{ts_probe = Current + Kcp13#kcp.probe_wait, probe = Kcp13#kcp.probe bor ?IKCP_ASK_SEND}; %% 更新下一次探查时间，设置此次为需要探查
                                    _ ->
                                        Kcp1
                                end
                        end;
                    _ ->
                        Kcp1#kcp{ts_probe = 0, probe_wait = 0} %% 如果知道远程端口尺寸，则无需设定探查时间与下次探查时间
                end,

            %% flush window probing commands
            {Seg1, Ptr2} =
                case Kcp2#kcp.probe band ?IKCP_ASK_SEND =/= 0 of
                    true ->
                        Ptr11 = make_space(?IKCP_OVERHEAD, Ptr1, Mtu),
                        {Seg#segment{cmd = ?IKCP_CMD_WASK}, encode(Seg, Ptr11)};
                    _ ->
                        {Seg, Ptr1}
                end,
            {Seg2, Ptr3} =
                case Kcp2#kcp.probe band ?IKCP_ASK_TELL =/= 0 of
                    true ->
                        Ptr21 = make_space(?IKCP_OVERHEAD, Ptr2, Mtu),
                        {Seg1#segment{cmd = ?IKCP_CMD_WINS}, encode(Seg1, Ptr21)};
                    _ ->
                        {Seg1, Ptr2}
                end,
            Kcp3 = Kcp2#kcp{probe = 0},

            %% calculate window size
            Cwnd = min(Kcp3#kcp.snd_wnd, Kcp3#kcp.rmt_wnd), %% 传输窗口是发送端与接收端中较小的一个
            Cwnd1 = ?IF(Kcp3#kcp.nocwnd == 0, min(Kcp3#kcp.cwnd, Cwnd)), %% 如果未取消拥塞控制,正在发送的数据大小与窗口尺寸比较

            %% sliding window, controlled by snd_nxt && sna_una+cwnd
            {Kcp4, NewSegsCount} = sliding_window(Kcp3#kcp.snd_queue, Kcp3, 0, Cwnd1),
            SndQueue = Kcp4#kcp.snd_queue,
            LenSndQueue = erlang:length(SndQueue),

            %%  如果有将snd_queue中的数据移动至snd_buf中，则需要将snd_queue中的对应数据删除
            Kcp5 = ?IF(NewSegsCount > 0, Kcp4#kcp{snd_queue = lists:sublist(SndQueue, NewSegsCount + 1, LenSndQueue - NewSegsCount)}, Kcp4),

            %% 设置重传策略
            %% calculate resent
            Resent = ?IF(Kcp5#kcp.fastresend =< 0, 4294967295, Kcp5#kcp.fastresend), %% 如果触发快速重传的重复ack个数 <= 0, 4294967295 = 0xffffffff
            Current = ?CURRENT,
            MinRto = Kcp5#kcp.interval,
            %% Change:新变更传输状态的数量，LostSegs:丢失片段数
            {Ptr4, Kcp6, MinRto1, Change, LostSegs} = bounds_check_elimination(Kcp5#kcp.snd_buf, Ptr3, Kcp5, Current, Resent, NewSegsCount, Seg, MinRto, 0, 0),

            %% flash remain segments
            flush_buffer(Ptr4),

            %% cwnd update
            Kcp7 =
                case Kcp6#kcp.nocwnd == 0 of
                    %%  update ssthresh
                    %%	rate halving, https://tools.ietf.org/html/rfc6937
                    true ->
                        Kcp61 =
                            case Change > 0 of
                                true ->
                                    Inflight = Kcp6#kcp.snd_nxt - Kcp6#kcp.snd_una,     %% 待发送的与未确认最小值得差值==未确认的总数
                                    Kcp6#kcp{
                                        ssthresh = ?IF(Inflight div 2 < ?IKCP_THRESH_MIN, ?IKCP_THRESH_MIN, Inflight div 2) %% 如果 拥塞窗口阈值 小于 拥塞窗口最小值
                                        ,cwnd = Kcp6#kcp.ssthresh + Resent              %% 拥塞窗口阈值+重传数量
                                        ,incr = Kcp6#kcp.cwnd * Kcp6#kcp.mss            %% 可发送的最大数据量=拥塞窗口*最大分片大小
                                    };
                                _ ->
                                    Kcp6
                            end,
                        %% congestion control, https://tools.ietf.org/html/rfc5681
                        Kcp62 =
                            case LostSegs > 0 of
                                true ->
                                    Kcp61#kcp{
                                        ssthresh = ?IF(Cwnd div 2 < ?IKCP_THRESH_MIN, ?IKCP_THRESH_MIN, Cwnd1 div 2)
                                        ,cwnd = 1
                                        ,incr = Kcp61#kcp.mss
                                    };
                                _ ->
                                    Kcp61
                            end,
                        case Kcp62#kcp.cwnd < 1 of
                            true ->
                                Kcp61#kcp{
                                    cwnd = 1
                                    ,incr = Kcp62#kcp.mss
                                };
                            _ ->
                                Kcp62
                        end;
                    _ ->
                        Kcp6
                end,
            {Kcp7, MinRto1}
    end.

%% 发送残留的数据
flush_buffer(<<>>) ->
    ok;
flush_buffer(Ptr) ->
    out_put(Ptr).

%% 将确定要检查的内容进行遍历
bounds_check_elimination([], Ptr, Kcp, _Current, _Resent, _NewSegsCount, _ThisSeg, MinRto, Change, LostSegs) ->
    {Ptr, Kcp, MinRto, Change, LostSegs};
bounds_check_elimination([#segment{xmit = Xmit, fastack = FastAck, resendts = Resendts} = Seg | Ref], Ptr, Kcp, Current, Resent, NewSegsCount, ThisSeg, MinRto, Change, LostSegs) ->
    case Seg#segment.acked == 1 of  %% 如果此记录以及被确认过
        true ->
            bounds_check_elimination(Ref, Ptr, Kcp, Current, Resent, NewSegsCount, ThisSeg, MinRto, Change, LostSegs);
        _ ->
            {Needsend, Seg1, Change1, LostSegs1} =
                if
                    Xmit == 0 -> {true, Seg#segment{    %% initial transmit 如果传输状态为0--> 未发送
                        rto = Kcp#kcp.rx_rto,           %% 重传超时时间
                        resendts = Current + Seg#segment.rto    %% 发送时间
                    }, Change, LostSegs};
                    FastAck >= Resent -> {true, Seg#segment{ %% fast retransmit 快速确认act数>快速重传数
                        fastack = 0,
                        rto = Kcp#kcp.rx_rto,
                        resendts = Current + Seg#segment.rto
                    }, Change + 1, LostSegs};
                    FastAck > 0 andalso NewSegsCount =:= 0 -> {true, Seg#segment{ %% early retransmit 快速确认数>0且没有新数据加入
                        fastack = 0,
                        rto = Kcp#kcp.rx_rto,
                        resendts = Current + Seg#segment.rto
                    }, Change + 1, LostSegs};
                    Current - Resendts >= 0 -> {true, Seg#segment{  %% RTO  当前时间已经达到重传时间的
                        fastack = 0,
                        rto = ?IF(Kcp#kcp.nodelay == 0, Kcp#kcp.rx_rto, Kcp#kcp.rx_rto div 2), %% 如果不启动无延迟模式(延迟)；当前Segment的每一次重传时间加rx_rto
                        resendts = Current + Seg#segment.rto
                    }, Change, LostSegs + 1};
                    true -> {false, Seg, Change, LostSegs}
                end,
            {Kcp1, Ptr1, Seg2} =
                case Needsend of
                    true ->
                        Seg12 = Seg1#segment{xmit = Seg1#segment.xmit + 1, ts = Current, wnd = ThisSeg#segment.wnd, una = ThisSeg#segment.una},
                        Need = ?IKCP_OVERHEAD + erlang:byte_size(Seg12#segment.data),
                        Ptr11 = make_space(Need, Ptr, Kcp#kcp.mtu),
                        Ptr12 = encode(Seg12, Ptr11),
                        Ptr13 = <<Ptr12/bytes, (Seg12#segment.data)/bytes>>,
                        Kcp11 =
                            case Seg12#segment.xmit >= Kcp#kcp.dead_link of
                                true->
                                    %% 连接状态（-1 表示断开连接）
                                    Kcp#kcp{state = -1};
                                _ ->
                                    Kcp
                            end,
                        {Kcp11, Ptr13, Seg12};
                    _ ->
                        {Kcp, Ptr, Seg1}
                end,
            Rto = Seg2#segment.resendts - Current,
            MinRto1 =
                case Rto > 0 andalso Rto < MinRto of
                    true -> Rto;
                    _ -> MinRto
                end,
            bounds_check_elimination(Ref, Ptr1, Kcp1, Current, Resent, NewSegsCount, ThisSeg, MinRto1, Change1, LostSegs1)
    end.

%% kcp.snd_nxt[待发送的sn]-(kcp.snd_una[已经确认的连续sn号]+cwnd[发送途中的数量])>=0
%% 表示发送中+未确认的已经大于cwnd的尺寸了，需要等待
sliding_window([], Kcp, NewSegsCount, _Cwnd) ->
    {Kcp, NewSegsCount};
sliding_window([NewSeg | SndQueue], Kcp, NewSegsCount, Cwnd) ->
    case Kcp#kcp.snd_nxt - Kcp#kcp.snd_una - Cwnd >= 0 of
        true->
            {Kcp, NewSegsCount};
        _ ->
            sliding_window(SndQueue,
                Kcp#kcp{
                snd_buf = Kcp#kcp.snd_buf ++ [NewSeg#segment{ %% 从开始位置取数据,将数据移动到snd_buf中去
                    conv = Kcp#kcp.conv, %% 客户端号，一个客户端的号码在同一次启动中是唯一的
                    cmd = ?IKCP_CMD_PUSH, %% 数据推出命令字
                    sn = Kcp#kcp.snd_nxt %% 设定
                    }],
                snd_nxt = Kcp#kcp.snd_nxt + 1
            }, NewSegsCount + 1, Cwnd)
    end.

%% acklist中数据发送
flush_acknowledges([], _Kcp, Seg, Ptr) ->
    {Seg, Ptr};
flush_acknowledges([Ack | AckList], Kcp, Seg, Ptr) ->
    Ptr1 = make_space(?IKCP_OVERHEAD, Ptr, Kcp#kcp.mtu),
    case Ack#segment.sn - Kcp#kcp.rcv_nxt >= 0 orelse AckList == [] of
        true ->
            {Seg#segment{sn = Ack#segment.sn, ts = Ack#segment.ts}, encode(Ptr, Seg)};
        _ ->
            flush_acknowledges(AckList, Kcp, Seg, Ptr1)
    end.

%% 删除Ptr中一个Seg
encode(Seg, Ptr) ->
    <<Ptr/bytes,
        (Seg#segment.conv):32/little-integer
        ,(Seg#segment.cmd):8/little-integer
        ,(Seg#segment.frg):8/little-integer
        ,(Seg#segment.wnd):16/little-integer
        ,(Seg#segment.ts):32/little-integer
        ,(Seg#segment.sn):32/little-integer
        ,(Seg#segment.una):32/little-integer
        ,(erlang:length(Seg#segment.data)):32/little-integer
    >>.

decode(Data) ->
    <<
        Conv:32/little-integer
        ,Cmd:8/little-integer
        ,Frg:8/little-integer
        ,Wnd:16/little-integer
        ,Ts:32/little-integer
        ,Sn:32/little-integer
        ,Una:32/little-integer
        ,Len:32/little-integer
    >> = Data,
    {Conv, Cmd, Frg, Wnd, Ts, Sn, Una, Len}.

%% makeSpace makes room for writing
make_space(Space, Ptr, Mtu) ->
    Size = erlang:byte_size(Ptr),
    %% 小数据打包,达到mtu大小再发送
    case Size + Space > Mtu of
        true ->
            out_put(Ptr),
            <<>>;
        _ ->
            Ptr
    end.

wnd_unused(Kcp) ->
    case length(Kcp#kcp.rcv_queue) < Kcp#kcp.rcv_wnd of
        true ->
            Kcp#kcp.rcv_wnd -  Kcp#kcp.rcv_queue;
        _ ->
            0
    end.

out_put(Buffer) ->
    111.
%%======================================================================================================================


%%======================================================================================================================
%% Input
%%======================================================================================================================
%%// Input a packet into kcp state machine.
%%//
%%// 'regular' indicates it's a real data packet from remote, and it means it's not generated from ReedSolomon
%%// codecs.
%%//
%%// 'ackNoDelay' will trigger immediate ACK, but surely it will not be efficient in bandwidth
%%/**
%% * 6.1 数据发送给接受端，接受端通过input进行接受，并解包receive buf，有确认的数据包recv_buf-->recv_queue
%% * 1. 解包
%% * 2. 确认是否有新的确认块，确认块需要重recv_buf-->recv_queue
%% * 3. 更新相关参数，主要是是否有确认过未删除，recv_buf，recv_queue的尺寸
%% */
input(Kcp, Data, Regular, AckNoDelay) ->
    SndUna = Kcp#kcp.snd_una,
    case erlang:byte_size(Data) < ?IKCP_OVERHEAD of
        true ->
            {Kcp, -1};
        _ ->

    end,
    1.
%%======================================================================================================================



%%======================================================================================================================
%% Recv
%%======================================================================================================================
%%/**
%% * 6.2 获取完整用户数据：从receive queue中进行拼装完整用户数据
%% * 1. 遍历rcv_queue中，是否可以获取到连续块却最后一块的frg=0的情况，如果存在，则提取一个完整用户数据；并删除rcv_queue中对应的数据块，释放空间
%% * 2. 提取完成后，遍历rcv_buf中，是否还有有效数据，更新到rcv_queue中；等待下次进行判断
%% */
recv(Buffer, Kcp) ->
    PeekSize = peek_size(Kcp),
    case PeekSize < 0 of
        true -> throw(-1)
    end,
    case PeekSize > length(Buffer) of
        true -> throw(-2)
    end,
    FastRecover = length(Kcp#kcp.rcv_queue) >= length(Kcp#kcp.rcv_wnd),
    {Res, N, Count} = merge_fragment(Kcp#kcp.rcv_queue, Kcp, <<>>, 0, 0),
    Kcp1 =
        case Count > 0 of
            true ->
                RcvQueue = Kcp#kcp.rcv_queue,
                LenRcvQueue = length(RcvQueue),
                Kcp#kcp{snd_queue = lists:sublist(RcvQueue, Count + 1, LenRcvQueue - Count)};
            _ -> Kcp
        end,
    {Count1, Kcp2} = loop_rcv_buf(Kcp1#kcp.rcv_buf, 0, Kcp1),
    Kcp3 =
        case Count1 > 0 of
            true->
                RcvQueue2 = Kcp2#kcp.rcv_queue,
                RcvBuf2 = Kcp2#kcp.rcv_buf,
                LenRcvBuf2 = length(RcvBuf2),
                Kcp2#kcp{rcv_queue = RcvQueue2 ++ RcvBuf2, rcv_buf = lists:sublist(RcvBuf2, Count + 1, LenRcvBuf2 - Count)};
            _ ->
                Kcp2
        end,
    Kcp4 =
        case length(Kcp3#kcp.rcv_queue) < Kcp3#kcp.rcv_wnd andalso FastRecover of
            true ->
                Probe = Kcp3#kcp.probe,
                Kcp3#kcp{probe = Probe bor ?IKCP_ASK_TELL};
            _ ->
                Kcp3
        end,
    {Res, N, Kcp4}.

loop_rcv_buf(_RcvBuf, Count, Kcp) ->
    {Count, Kcp};
loop_rcv_buf([#segment{sn = Sn, frg = Frg} | RcvBuf], Count, #kcp{rcv_nxt = RcvNxt, rcv_queue = RcvQueue, rcv_wnd = RcvWnd} = Kcp) ->
    case Sn == RcvNxt andalso length(RcvQueue) + Count < RcvWnd of
        true ->
            loop_rcv_buf(RcvBuf, Count + 1, Kcp#kcp{rcv_nxt = RcvNxt + 1}) ;
        _ ->
            {Count, Kcp}
    end.


%% checks the size of next message in the recv queue
peek_size(#kcp{rcv_queue = RcvQueue}) ->
    case length(RcvQueue) of
        0 -> -1;
        _ ->
            [#segment{data = Data, frg = Frg}| _] = RcvQueue,
            case Frg of
                0 ->
                    length(Data);
                _ ->
                    case length(RcvQueue) < Frg + 1 of
                        true -> -1;
                        _ ->
                            loop_rcv_queue(RcvQueue, 0)
                    end
            end
    end.

merge_fragment(_, _, Res, N, Count) ->
    {Res, N, Count};
merge_fragment([#segment{data = SegData, frg = SegFrg} = Seg | RcvQueue], Kcp, Res, N, Count) ->
    Res1 = <<Res/bytes, SegData/bytes>>,
    N1 = N + erlang:byte_size(SegData),
    case SegFrg of
        0 ->
            {Res1, N1, Count + 1};
        _ ->
            merge_fragment(RcvQueue, Kcp, Res1, N1, Count + 1)
    end.

loop_rcv_queue([], Len) ->
    Len;
loop_rcv_queue([#segment{data = Data, frg = Frg} | RcvQueue], Len) ->
    NewLen = Len + length(Data),
    case Frg == 0 of
        true ->
            NewLen;
        _ ->
            loop_rcv_queue(RcvQueue, NewLen)
    end.
%%======================================================================================================================