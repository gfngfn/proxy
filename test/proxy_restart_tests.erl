-module(proxy_restart_tests).

-include_lib("eunit/include/eunit.hrl").

-define(assertDown(Pid, Reason),
        (fun () -> receive {'DOWN', _, _, Pid, _Reason} -> ?assertMatch(Reason, _Reason) after 100 -> ?assert(timeout) end end)()).

restart_test_() ->
    [
     {"指定回数だけ実プロセスの再起動が行われる",
      fun () ->
              Count = 3,
              Parent = self(),
              proxy:spawn_opt(fun () ->
                                      Parent ! hello
                              end,
                              [{proxy_restart, [{max_restart, Count}]}],
                              [link]),
              lists:foreach(
                fun (_) ->
                        receive
                            hello -> ?assert(true)
                        end
                end,
                lists:seq(1, Count))
      end},
     {"intervalの設定が正常に設定されている",
      fun () ->
              Count = 5,
              Parent = self(),
              proxy:spawn_opt(fun () ->
                                      Parent ! hello
                              end,
                              [{proxy_restart, [{interval, 10}, {max_interval, 20}, {max_restart, Count}]}],
                              [link]),
              [_ | Result] = [begin
                                  {Time, _} = timer:tc(fun() -> receive hello -> ok end end),
                                  Time
                              end || _ <- lists:seq(1, Count)],
              Allowance = 1.1, % 許容誤差
              [?assert(R >= 10 * 1000 andalso R < 30 * 1000 * Allowance) || R <- Result]
      end},
     {"回数が残っている場合でもEXITシグナルを受け取ったら、実プロセスもダウンする: プロキシが一つの場合",
      fun () ->
              Count = 3,
              Parent = self(),
              ProxyPid =
                  proxy:spawn(fun () ->
                                      Parent ! {real_pid, self()},
                                      timer:sleep(infinity)
                              end,
                              [{proxy_restart, [{max_restart, Count}]}]),
              RealPid = receive {real_pid, Pid} -> Pid end,

              monitor(process, ProxyPid),
              monitor(process, RealPid),
              exit(ProxyPid, shutdown),

              ?assertDown(ProxyPid, shutdown),
              ?assertDown(RealPid, shutdown)
      end},
     {"回数が残っている場合でもEXITシグナルを受け取ったら、実プロセスもダウンする: プロキシが複数の場合",
      fun () ->
              Count = 3,
              Parent = self(),
              ProxyPid =
                  proxy:spawn(fun () ->
                                      Parent ! {real_pid, self()},
                                      timer:sleep(infinity)
                              end,
                              [{proxy_restart, [{max_restart, Count}]},
                               {proxy_lifetime, []}]),
              RealPid = receive {real_pid, Pid} -> Pid end,

              monitor(process, ProxyPid),
              monitor(process, RealPid),
              exit(ProxyPid, shutdown),

              ?assertDown(ProxyPid, shutdown),
              ?assertDown(RealPid, shutdown)
      end},
     {"proxyプロセスにlinkしているプロセスが死んだ場合の挙動は、標準に合わせる",
      fun () ->
              ProxyPid =
                  proxy:spawn(fun () -> timer:sleep(infinity) end,
                              [{proxy_restart, []},
                               {proxy_sleep_handle, []}]),
              monitor(process, ProxyPid),

              %% linkプロセスがnormalで死んだ => proxyは死なない
              {LinkPid0, _} = spawn_monitor(fun () -> link(ProxyPid), exit(normal) end),
              ?assertDown(LinkPid0, normal),
              timer:sleep(10), % 適当に待つ
              ?assert(erlang:is_process_alive(ProxyPid)),

              %% linkプロセスがnormal以外で死んだ => proxyも同じ理由で死ぬ
              {LinkPid1, _} = spawn_monitor(fun () -> link(ProxyPid), exit(shutdown) end),
              ?assertDown(LinkPid1, shutdown),
              ?assertDown(ProxyPid, shutdown)
      end}
    ].
