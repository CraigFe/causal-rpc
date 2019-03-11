open Lwt.Infix
open Trace_rpc
open Intmap

module GitBackend = Irmin_unix.Git.FS.G
module I = IntPair (Trace_rpc_unix.Make)(GitBackend)

open I

let create_client directory remote =
  IntClient.empty ~directory
    ~local_uri:("file://" ^ directory)
    ~remote_uri:("file://" ^ remote)
    ~name:"clientA"
    ~initial:Int64.one

let test_single_rpc () =
  let root = "/tmp/irmin/test_unicast/single_rpc/" in

  (* Create a simple client *)
  create_client (root ^ "clientA") (root ^ "server")
  >>= fun client -> IntMap.empty ~directory:(root ^ "server") ()
  >>= fun server -> IntMap.start server
  >>= (fun () ->
  let rec inner n max =
    if n = max then Lwt.return_unit
    else
      let init = Core.Time_ns.now () in
      IntClient.rpc increment_op Interface.Unit client
        >|= (fun _ -> let final = Core.Time_ns.now () in
              let span = Core.Time_ns.abs_diff init final in
              print_string @@ Fmt.strf "%a,%a\n" Core.Time_ns.pp final Core.Time_ns.Span.pp span)
      >>= fun _ -> inner (n+1) max
  in inner 1 10_000)

let () =
  Lwt_main.run (test_single_rpc ())

