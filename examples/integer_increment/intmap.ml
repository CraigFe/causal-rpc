open Trace_rpc

module Int = struct
  type t = int
  let (=) = Pervasives.(=)
  let of_string = int_of_string
  let to_string = string_of_int
end

module Ops = struct
  type t = int
  let iter x = x + 1
end

module IntMap = Map.Make(Int)(Ops)
module IntWorker = Worker.Make(Int)(Ops)
