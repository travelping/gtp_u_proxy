%% Copyright 2016, Travelping GmbH <info@travelping.com>

%% This program is free software; you can redistribute it and/or
%% modify it under the terms of the GNU General Public License
%% as published by the Free Software Foundation; either version
%% 2 of the License, or (at your option) any later version.

-module(gtp_u_edp_handler).

%% API
-export([start_link/7, add_tunnel/6, handle_msg/6]).

-include_lib("gtplib/include/gtp_packet.hrl").
-include("include/gtp_u_edp.hrl").

-define('Tunnel Endpoint Identifier Data I',	{tunnel_endpoint_identifier_data_i, 0}).
-define('GTP-U Peer Address',			{gsn_address, 0}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link(Port, PeerIP, LocalTEI, RemoteTEI, Owner, HandlerMod, HandlerArgs) ->
    HandlerMod:start_link(Port, PeerIP, LocalTEI, RemoteTEI, Owner, HandlerArgs).

add_tunnel(Port, PeerIP, LocalTEI, RemoteTEI, Owner, {Handler, HandlerArgs}) ->
    HandlerMod = map_handler(Handler),
    gtp_u_edp_handler_sup:add_tunnel(Port, PeerIP, LocalTEI, RemoteTEI, Owner, HandlerMod, HandlerArgs).

handle_msg(Name, Socket, Req, IP, Port, #gtp{type = g_pdu, tei = TEI, seq_no = _SeqNo} = Msg)
  when is_integer(TEI), TEI /= 0 ->
    case gtp_u_edp:lookup({Name, TEI}) of
	Handler when is_pid(Handler) ->
	    handler_handle_msg(Handler, Name, Req, IP, Port, Msg);
	_ ->
	    gtp_u_edp_port:send_error_indication(Socket, IP, TEI, [{udp_port, Port}]),
	    gtp_u_edp_metrics:measure_request_error(Req, context_not_found),
	    ok
    end;
handle_msg(Name, _Socket, Req, IP, Port,
	   #gtp{type = error_indication,
		ie = #{?'Tunnel Endpoint Identifier Data I' :=
			   #tunnel_endpoint_identifier_data_i{tei = TEI}}} = Msg) ->
    lager:notice("error_indication from ~p:~w, TEI: ~w", [IP, Port, TEI]),
    case gtp_u_edp:lookup({Name, {remote, IP, TEI}}) of
	Handler when is_pid(Handler) ->
	    handler_handle_msg(Handler, Name, Req, IP, Port, Msg);
	_ ->
	    gtp_u_edp_metrics:measure_request_error(Req, context_not_found),
	    ok
   end;
handle_msg(_Name, _Socket, _Req, IP, Port, #gtp{type = Type, tei = TEI, seq_no = _SeqNo}) ->
    lager:notice("~p from ~p:~w, TEI: ~w, SeqNo: ~w", [Type, IP, Port, TEI, _SeqNo]),
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
handler_handle_msg(Handler, Name, Req, IP, Port, Msg) ->
    gen_server:cast(Handler, {handle_msg, Name, Req, IP, Port, Msg}).

map_handler(forward) ->
    gtp_u_edp_forwarder.
