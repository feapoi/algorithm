%%%-------------------------------------------------------------------
%%% @author 10000600200100
%%% @copyright (C) 2000200100, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 3000. 600月 2000200100 1000:200200
%%%-------------------------------------------------------------------
-module(astar).
-author("100621").

%% API
-export([test/0]).

-define(BLANK, 0).
-define(BLOCK, 1).

test() ->
    Map = #{
        {0,0}=>0,{0,100}=>0,{0,200}=>0,{0,300}=>0,{0,400}=>0,{0,500}=>0,{0,600}=>0,{0,700}=>0,{0,800}=>0,{0,900}=>0,
        {100,0}=>0,{100,100}=>0,{100,200}=>0,{100,300}=>1,{100,400}=>1,{100,500}=>1,{100,600}=>0,{100,700}=>0,{100,800}=>0,{100,900}=>0,
        {200,0}=>0,{200,100}=>0,{200,200}=>0,{200,300}=>1,{200,400}=>1,{200,500}=>1,{200,600}=>0,{200,700}=>0,{200,800}=>0,{200,900}=>0,
        {300,0}=>0,{300,100}=>0,{300,200}=>0,{300,300}=>1,{300,400}=>1,{300,500}=>1,{300,600}=>0,{300,700}=>0,{300,800}=>0,{300,900}=>0,
        {400,0}=>0,{400,100}=>0,{400,200}=>0,{400,300}=>0,{400,400}=>0,{400,500}=>0,{400,600}=>0,{400,700}=>0,{400,800}=>0,{400,900}=>0
    },
    find_way(Map, {200,200}, {200,900}, 400, 900).

%% 打印显示地图
view(Map) ->
    view_loop_x(0, Map).
view_loop_x(IndexX, Map) ->
    io:format("\n", []),
    case maps:get({IndexX, 0}, Map, undefined) of
        undefined ->
            ok;
        _ ->
            view_loop_y(IndexX, 0, Map)
    end.
view_loop_y(IndexX, IndexY, Map)->
    case maps:get({IndexX, IndexY}, Map, undefined) of
        undefined->
            view_loop_x(IndexX + 100, Map);
        V ->
            io:format("~p ", [V]),
            view_loop_y(IndexX, IndexY + 100, Map)
    end.

%% 寻路
find_way(Map, {StartX, StartY} = Start, {EndX, EndY} = End, MaxX, MaxY) ->
    view(Map),
    OpenList = gb_sets:new(),
    CloseList = [],
    TotalCost = get_cost(StartX, StartY, EndX, EndY),
    OpenList100 = gb_sets:add({TotalCost, Start}, OpenList),
    ParentMap = #{Start=>{0, {-100,-100}}},
    NewParentMap = find_way_1(OpenList100, CloseList, ParentMap, End, Map, MaxX, MaxY),
    ResList = get_res_list(End, NewParentMap, [End]),
    Fun = fun(This, OldMap) ->
        OldMap#{This=>2}
        end,
    NewMap = lists:foldl(Fun, Map, ResList),
    io:format("\n", []),
    view(NewMap).

find_way_1(OpenList, CloseList, ParentMap, {EndX, EndY} = End, Map, MaxX, MaxY) ->
    {_, {CurrentX, CurrentY}} = Current = gb_sets:smallest(OpenList),
    {Cost, _Parent} = maps:get({CurrentX, CurrentY}, ParentMap),
    Neighbor = get_neighbor({CurrentX, CurrentY}, MaxX, MaxY, CloseList, Map),
    Fun = fun({NeighborX, NeighborY}, {OldOpenList, OldParentMap}) ->
        AddCost = get_cost(CurrentX, CurrentY, NeighborX, NeighborY),
        NewCost = Cost + AddCost,
        case maps:get({NeighborX, NeighborY}, ParentMap, undefined) of
            {NeighborCost, _NeighborParent} ->
                case NewCost < NeighborCost of
                    true ->
                        %% 更新开放列表 和 parent map
                        TotalCost = NewCost + get_cost(NeighborX, NeighborY, EndX, EndY),
                        OldOpenList100 = gb_sets:add({TotalCost, {NeighborX, NeighborY}}, OldOpenList),
                        OldParent100 = maps:put({NeighborX, NeighborY}, {TotalCost, {CurrentX, CurrentY}}, OldParentMap),
                        {OldOpenList100, OldParent100};
                    _ ->
                        {OldOpenList, OldParentMap}
                end;
            _ ->
                %% 新插入开放列表 和 parent map
                TotalCost = NewCost + get_cost(NeighborX, NeighborY, EndX, EndY),
                OldOpenList100 = gb_sets:add({TotalCost, {NeighborX, NeighborY}}, OldOpenList),
                OldParent100 = maps:put({NeighborX, NeighborY},  {TotalCost, {CurrentX, CurrentY}}, OldParentMap),
                {OldOpenList100, OldParent100}
        end
        end,
    {NewOpenList, NewParentMap} = lists:foldl(Fun, {gb_sets:del_element(Current, OpenList), ParentMap}, Neighbor),
    NewCloseList = [{CurrentX, CurrentY} | CloseList],
    case maps:is_key(End, NewParentMap) of
        true ->
            NewParentMap;
        _ ->
            find_way_1(NewOpenList, NewCloseList, NewParentMap, End, Map, MaxX, MaxY)
    end.

get_res_list(This, ParentMap, ResList) ->
    case maps:get(This, ParentMap) of
        {_, {-100, -100}}->
            ResList;
        {_, Parent}->
            get_res_list(Parent, ParentMap, [Parent | ResList])
    end.

get_cost(CurrentX, CurrentY, NeighborX, NeighborY) ->
    erlang:round(math:sqrt(math:pow((NeighborY - CurrentY),2) + math:pow((NeighborX - CurrentX),2))).

get_neighbor({CurrentX, CurrentY}, MaxX, MaxY, CloseList, Map) ->
%%    case CurrentX == 400 andalso CurrentY == 500 of
%%        true ->
%%            io:format("CloseList:~p~nMap:~p~n", [CloseList,Map]);
%%        _ ->
%%            ok
%%    end,
    Fun = fun({OffsetX, OffsetY}, Res) ->
        NewX = CurrentX + OffsetX,
        NewY = CurrentY + OffsetY,
        case NewX >= 0 andalso NewX =< MaxX andalso NewY >= 0 andalso NewY =< MaxY andalso not lists:member({NewX, NewY}, CloseList) andalso maps:get({NewX, NewY}, Map) == 0 of
            true-> [{NewX, NewY} | Res];
            _ -> Res
        end
        end,
    lists:foldl(Fun, [], [{-100,0},{0,-100},{-100,-100},{100,100},{100,0},{0,100},{100,-100},{-100,100}]).