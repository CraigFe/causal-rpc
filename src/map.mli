
exception Empty_queue

(** A task is an operation, a list of parameters and a key specifying the value
    on which to perform the operation *)

type ('v, 'jq) contents =
  | Value of 'v
  | Task_queue of Task_queue.t
  | Job_queue of 'jq

module type QUEUE_TYPE = sig
  type t
  type job

  val t: t Irmin.Type.t
  val job: job Irmin.Type.t
end

module type JOB_QUEUE = sig
  type t
  (** The type of job queues *)

  type job
  (** The type of jobs *)

  module Store: Irmin.KV

  module Type: QUEUE_TYPE
    with type t = t
     and type job = job

  module type IMPL = sig
    val job_of_string: string -> job
    val job_to_string: job -> string
    val job_equal: job -> job -> bool

    val is_empty: Store.t -> bool Lwt.t
    val push: job -> Store.t -> unit Lwt.t
    val pop: Store.t -> job Lwt.t
    val peek_opt: Store.t -> job option Lwt.t
  end

  module Impl: IMPL
end

module MakeContents (Val: Irmin.Contents.S) (JQueue: QUEUE_TYPE): Irmin.Contents.S
  with type t = (Val.t, JQueue.t) contents

exception Malformed_params of string
exception Protocol_error of string
exception Timeout

module type S = sig
  module Value: Irmin.Contents.S

  type key = string
  (** The type of the map keys *)

  type queue
  (** The type of the job queue *)

  type t
  (** The type of maps from type [key] to type [value] *)

  module Contents: Irmin.Contents.S with type t = (Value.t, queue) contents

  module Store: Store.S
    with type key = string list
     and type step = string
     and type contents = Contents.t
     and type branch = string

  module Sync: Irmin.SYNC with type db = Store.t
  module JobQueue: JOB_QUEUE with module Store = Store
  module Operation: Interface.OPERATION with module Val = Value

  type 'a params = 'a Interface.MakeOperation(Value).params

  exception Internal_type_error
  exception Store_error of Store.write_error

  (* -- TESTING PURPOSES --------------------------------- *)
  val task_queue_is_empty: t -> bool Lwt.t
  val job_queue_is_empty: t -> bool Lwt.t
  val generate_task_queue: 'a Operation.Unboxed.t -> 'a params -> t -> (Value.t, queue) contents Lwt.t
  (* ----------------------------------------------------- *)

  val of_store: Sync.db -> t
  (** Return the map corresponding to an underlying store representation *)

  val to_store: t -> Sync.db
  (** Return the underlying store representation. TODO: remove. Nothing should need access
      to this, but it is currently being used by the worker. *)

  val empty: ?directory:string -> unit -> t Lwt.t
  (** The empty map. *)

  val is_empty: t -> bool Lwt.t
  (** Test whether a map is empty or not. *)

  val mem: key -> t -> bool Lwt.t
  (** [mem x m] returns true iff [m] contains a binding for [x] *)

  val add: ?message:string -> key -> Value.t -> t -> t Lwt.t
  (** [add x y m] returns a map containing the same bindings as [m],
      plus a binding of [x] to [y]. If [x] was already bound in [m],
      its previous binding is replaced. *)

  val add_all: ?message:string -> (key * Value.t) list -> t -> t Lwt.t
  (** [add bind_list m] returns a map containing the same bindings as [m],
      plus bindings from k to v for all (k, v) in [bind_list]. If any k
      was already bound in [m], its previous binding is replaced. *)

  val find: key -> t -> Value.t Lwt.t
  (** [find x m] returns the current binding of [x] in [m],
      or raises [Not_found] if no such binding exists. *)

  val remove: key -> t -> t Lwt.t
  (** [remove x m] returns a map containing the same bindings as [m],
      except for [x] which is unbound in the returned map. *)

  val size: t -> int Lwt.t
  (** Return the number of bindings in the map *)

  val keys: t -> key list Lwt.t
  (** Return a list of keys in the map *)

  val values: t -> Value.t list Lwt.t
  (** Return a list of values in the map *)

  val map: ?timeout:float -> 'a Operation.Unboxed.t -> 'a params -> t -> t Lwt.t
  (** [map m] returns a map with the same domain as [m] in which
      the associated value [a] of all bindings of [m] have been
      replaced by the result of applying _a_ function to [a] *)
end

module Make
    (Desc: Interface.DESC)
    (QueueType: QUEUE_TYPE)
    (JQueueMake: functor
       (Val: Irmin.Contents.S)
       (St: Store.S
        with type key = Irmin.Path.String_list.t
         and type step = string
         and module Key = Irmin.Path.String_list
         and type contents = (Val.t, QueueType.t) contents
         and type branch = string)
       -> (JOB_QUEUE with module Store = St)): S
  with module Value = Desc.Val
   and module Operation = Interface.MakeOperation(Desc.Val)
   and type queue = QueueType.t
(** Functor building an implementation of the map structure given:
     - a value for the map to contain
     - a set of operations on that type
     - a queue type
     - a job queue implementation *)
