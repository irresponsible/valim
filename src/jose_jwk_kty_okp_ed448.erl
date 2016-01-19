%% -*- mode: erlang; tab-width: 4; indent-tabs-mode: 1; st-rulers: [70] -*-
%% vim: ts=4 sw=4 ft=erlang noet
%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pixid.com>
%%% @copyright 2014-2016, Andrew Bennett
%%% @doc
%%%
%%% @end
%%% Created :  15 Jan 2016 by Andrew Bennett <andrew@pixid.com>
%%%-------------------------------------------------------------------
-module(jose_jwk_kty_okp_ed448).
-behaviour(jose_jwk).
-behaviour(jose_jwk_kty).

%% jose_jwk callbacks
-export([from_map/1]).
-export([to_key/1]).
-export([to_map/2]).
-export([to_public_map/2]).
-export([to_thumbprint_map/2]).
%% jose_jwk_kty callbacks
-export([generate_key/1]).
-export([generate_key/2]).
-export([key_encryptor/3]).
-export([sign/3]).
-export([signer/3]).
-export([verify/4]).
%% API
-export([from_okp/1]).
-export([from_openssh_key/1]).
-export([to_okp/1]).
-export([to_openssh_key/2]).

%% Macros
-define(crv, <<"Ed448">>).
-define(secretbytes, 57).
-define(publickeybytes, 57).
-define(secretkeybytes, 114).

%% Types
-type publickey() :: << _:456 >>.
-type secretkey() :: << _:912 >>.
-type key() :: publickey() | secretkey().

-export_type([key/0]).

%%====================================================================
%% jose_jwk callbacks
%%====================================================================

from_map(F = #{ <<"kty">> := <<"OKP">>, <<"crv">> := ?crv, <<"d">> := D, <<"x">> := X }) ->
	<< Secret:?secretbytes/binary >> = base64url:decode(D),
	<< PK:?publickeybytes/binary >> = base64url:decode(X),
	SK = << Secret/binary, PK/binary >>,
	{SK, maps:without([<<"crv">>, <<"d">>, <<"kty">>, <<"x">>], F)};
from_map(F = #{ <<"kty">> := <<"OKP">>, <<"crv">> := ?crv, <<"x">> := X }) ->
	<< PK:?publickeybytes/binary >> = base64url:decode(X),
	{PK, maps:without([<<"crv">>, <<"kty">>, <<"x">>], F)}.

to_key(PK = << _:?publickeybytes/binary >>) ->
	PK;
to_key(SK = << _:?secretkeybytes/binary >>) ->
	SK.

to_map(PK = << _:?publickeybytes/binary >>, F) ->
	F#{
		<<"crv">> => ?crv,
		<<"kty">> => <<"OKP">>,
		<<"x">> => base64url:encode(PK)
	};
to_map(<< Secret:?secretbytes/binary, PK:?publickeybytes/binary >>, F) ->
	F#{
		<<"crv">> => ?crv,
		<<"d">> => base64url:encode(Secret),
		<<"kty">> => <<"OKP">>,
		<<"x">> => base64url:encode(PK)
	}.

to_public_map(PK = << _:?publickeybytes/binary >>, F) ->
	to_map(PK, F);
to_public_map(<< _:?secretbytes/binary, PK:?publickeybytes/binary >>, F) ->
	to_public_map(PK, F).

to_thumbprint_map(K, F) ->
	maps:with([<<"crv">>, <<"kty">>, <<"x">>], to_public_map(K, F)).

%%====================================================================
%% jose_jwk_kty callbacks
%%====================================================================

generate_key(Seed = << _:?secretbytes/binary >>) ->
	{_PK, SK} = jose_curve448:ed448_keypair(Seed),
	{SK, #{}};
generate_key({okp, 'Ed448', Seed = << _:?secretbytes/binary >>}) ->
	generate_key(Seed);
generate_key({okp, 'Ed448'}) ->
	{_PK, SK} = jose_curve448:ed448_keypair(),
	{SK, #{}}.

generate_key(KTY, Fields)
		when is_binary(KTY)
		andalso (byte_size(KTY) =:= ?publickeybytes
			orelse byte_size(KTY) =:= ?secretkeybytes) ->
	{NewKTY, OtherFields} = generate_key({okp, 'Ed448'}),
	{NewKTY, maps:merge(maps:remove(<<"kid">>, Fields), OtherFields)}.

key_encryptor(KTY, Fields, Key) ->
	jose_jwk_kty:key_encryptor(KTY, Fields, Key).

sign(Message, 'Ed448', SK = << _:?secretkeybytes/binary >>) ->
	jose_curve448:ed448_sign(Message, SK).

signer(<< _:?secretkeybytes/binary >>, _Fields, _PlainText) ->
	#{
		<<"alg">> => ?crv
	}.

verify(Message, 'Ed448', Signature, << _:?secretbytes/binary, PK:?publickeybytes/binary >>) ->
	verify(Message, 'Ed448', Signature, PK);
verify(Message, 'Ed448', Signature, PK = << _:?publickeybytes/binary >>) ->
	jose_curve448:ed448_verify(Signature, Message, PK).

%%====================================================================
%% API functions
%%====================================================================

from_okp({'Ed448', SK = << Secret:?secretbytes/binary, PK:?publickeybytes/binary >>}) ->
	case jose_curve448:ed448_secret_to_public(Secret) of
		PK ->
			{SK, #{}};
		_ ->
			erlang:error(badarg)
	end;
from_okp({'Ed448', PK = << _:?publickeybytes/binary >>}) ->
	{PK, #{}}.

from_openssh_key({<<"ssh-ed448">>, _PK, SK, Comment}) ->
	{KTY, OtherFields} = from_okp({'Ed448', SK}),
	case Comment of
		<<>> ->
			{KTY, OtherFields};
		_ ->
			{KTY, maps:merge(#{ <<"kid">> => Comment }, OtherFields)}
	end.

to_okp(SK = << _:?secretkeybytes/binary >>) ->
	{'Ed448', SK};
to_okp(PK = << _:?publickeybytes/binary >>) ->
	{'Ed448', PK}.

to_openssh_key(SK = << _:?secretbytes/binary, PK:?publickeybytes/binary >>, F) ->
	Comment = maps:get(<<"kid">>, F, <<>>),
	jose_jwk_openssh_key:to_binary([[{{<<"ssh-ed448">>, PK}, {<<"ssh-ed448">>, PK, SK, Comment}}]]).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------