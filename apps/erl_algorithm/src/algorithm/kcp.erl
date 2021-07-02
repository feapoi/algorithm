%%%-------------------------------------------------------------------
%%% @author 100621
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(kcp).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

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
    conv = 0,mtu = ?IKCP_MTU_DEF,mss = ?IKCP_MTU_DEF - ?IKCP_OVERHEAD,state = 0
    ,snd_una = 0,snd_nxt = 0,rcv_nxt = 0
    ,ssthresh = ?IKCP_THRESH_INIT
    ,rx_rttvar = 0,rx_srtt = 0
    ,rx_rto = ?IKCP_RTO_DEF,rx_minrto = ?IKCP_RTO_MIN
    ,snd_wnd = ?IKCP_WND_SND,rcv_wnd = ?IKCP_WND_RCV,rmt_wnd = ?IKCP_WND_RCV,cwnd = 0,probe = 0
    ,interval = ?IKCP_INTERVAL,ts_flush = ?IKCP_INTERVAL
    ,nodelay = 0,updated = 0
    ,ts_probe = 0,probe_wait = 0
    ,dead_link = ?IKCP_DEADLINK,incr = 0
    ,fastresend = 0
    ,nocwnd = 0, stream = 0
    ,snd_queue = [], rcv_queue = [], snd_buf = [], rcv_buf = []
    ,acklist = []
    ,buffer = <<>>
    ,reserved = 0
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
%% recv
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

    Buffer = Kcp#kcp.buffer,        %% 默认情况buffer=mtu的大小
    LenBuffer = length(Buffer),
    Ptr = lists:sublist(Buffer, Kcp#kcp.reserved + 1, LenBuffer - Kcp#kcp.reserved),    %% keep n bytes untouched 默认情况ptr等于mtu-kcp.reserved

    Ptr1 = make_space(?IKCP_OVERHEAD, Buffer, Ptr, Kcp#kcp.mtu, Kcp#kcp.reserved),
    1.


flush_acknowledges([], Kcp, Seg, Space, Buffer, Ptr) ->
    {Seg, Ptr};
flush_acknowledges([Ack | AckList], Kcp, Seg, Space, Buffer, Ptr) ->
    Ptr1 = make_space(?IKCP_OVERHEAD, Buffer, Ptr, Kcp#kcp.mtu, Kcp#kcp.reserved),
    case Ack#segment.sn - Kcp#kcp.rcv_nxt >= 0 orelse AckList == [] of
        true ->
            {Seg#segment{sn = Ack#segment.sn, ts = Ack#segment.ts}, encode(Ptr)};
        _ ->
            flush_acknowledges(AckList, Kcp, Seg, Space, Buffer, Ptr1)
    end.

encode(Seg, Ptr) ->
    .

%% makeSpace makes room for writing
make_space(Space, Buffer, Ptr, Mtu, Reserved) ->
    Size = length(Buffer) - length(Ptr),
    case Size + Space > Mtu of
        true ->
            out_put(Buffer, Size),
            lists:sublist(Buffer, Reserved);
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

out_put(Buffer, Size) ->
    111.
%%======================================================================================================================


%%======================================================================================================================
%% recv
%%======================================================================================================================
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
                Kcp#kcp{snd_queue = lists:sublist(RcvQueue, Count, LenRcvQueue - Count)};
            _ -> Kcp
        end,
    {Count1, Kcp2} = loop_rcv_buf(Kcp1#kcp.rcv_buf, 0, Kcp1),
    Kcp3 =
        case Count1 > 0 of
            true->
                RcvQueue2 = Kcp2#kcp.rcv_queue,
                RcvBuf2 = Kcp2#kcp.rcv_buf,
                LenRcvBuf2 = length(RcvBuf2),
                Kcp2#kcp{rcv_queue = RcvQueue2 ++ RcvBuf2, rcv_buf = lists:sublist(RcvBuf2, Count, LenRcvBuf2 - Count)};
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