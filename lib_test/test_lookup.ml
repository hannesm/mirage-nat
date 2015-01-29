open OUnit2
open Lookup

let (empty_table : Lookup.table) = empty ()
let default_table () =
  let t = Hashtbl.create 20 in
  let t = insert t 6 ((Ipaddr.of_string_exn "1.2.3.4"), 6000) (Ipaddr.of_string_exn
                                                                  "192.168.3.11",
                                                               80) in
  let t = insert t 17 ((Ipaddr.of_string_exn "::1"), 1234) (Ipaddr.of_string_exn
                                                      "10.1.2.3", 6667) in
  t

let basic_lookup context =
  let t = default_table () in
  assert_equal 
    (lookup t 6 (Ipaddr.of_string_exn "1.2.3.4") 6000)
    (Some (Ipaddr.of_string_exn "192.168.3.11", 80));
  assert_equal 
    (lookup t 6 (Ipaddr.of_string_exn "192.168.3.11") 80)
    (Some (Ipaddr.of_string_exn "1.2.3.4", 6000));
  assert_equal 
    (lookup t 4 (Ipaddr.of_string_exn "1.2.3.4") 6000)
    None;
  assert_equal 
    (lookup t 6 (Ipaddr.of_string_exn "8.8.8.8") 6000)
    None;
  assert_equal 
    (lookup t 6 (Ipaddr.of_string_exn "0.0.0.0") 6000)
    None
  (* TODO: with an empty table, any randomized check does not succeed *)
(* (todo: generator of random ips/ports) *)

let crud context =
  let module QC = QuickCheck in
  (* create, update, delete work as expected *)
  (* propositions: inserting then looking up results in input being found;
     deleting then looking up results in input not being found *)
  (* ideally we'd do this as 
    "make an empty table, 
    insert a batch of random things, 
    test that they're all there and correct,
    delete all of them, 
    test that they're not there, 
     test that nothing's there" *)
  let prop_cruds_as_expected input (* where input is a list of random proto ->
                                      ip,port -> ip,port *) =
    let h = empty () in
    let mem_bidirectional table protocol left right =
      let left_res = lookup table protocol (fst left) (snd left) in
      let right_res = lookup table protocol (fst right) (snd right) in
      match left_res, right_res with
      | Some right, Some left -> true 
      | None, _ | _, None -> false
    in
    ignore (List.map (fun (protocol, left, right) -> insert h protocol left right)
              input); 
    let all_there = List.fold_left (fun continue (protocol, left, right) -> (
        match continue with
        | true -> mem_bidirectional h protocol left right
        | false -> false
        )) true input
    in
    all_there (* TODO: deletes *)
  in
  let arbitrary_table_entry_list =
    QC.arbitrary_list Arbitrary.arbitrary_table_entry
  in
  let show_table_entry (proto, left, right) = Printf.sprintf "protocol %d: %s, %d
      <-> %s, %d" proto (Ipaddr.to_string (fst left)) (snd left)
      (Ipaddr.to_string (fst right)) (snd right)
  in
  let testable_entries_to_boolean = QC.quickCheck (QC.testable_fun
                                          arbitrary_table_entry_list
                                          (QC.show_list show_table_entry)
                                          QC.testable_bool)
  in
  let result = testable_entries_to_boolean prop_cruds_as_expected in
  assert_equal ~printer:Arbitrary.qc_printer QC.Success result

let overlapping_updates context =
  let old_mapping = (Ipaddr.of_string_exn "1.2.3.4", 6000) in
  let pivot = (Ipaddr.of_string_exn "192.168.3.11", 80) in
  let new_mapping = (Ipaddr.of_string_exn "8.8.4.4", 53417) in
  let t = insert (default_table ()) 6 pivot new_mapping
  in
  (* t already contained a definition for 192.168.3.11 *)
  (* results should either be the preexisting mapping, or the new mapping, 
     but not an entry for one half of the preexisting mapping and the two halves
     of our new mapping *)
  let is_consistent t =
    match lookup t 6 (fst pivot) (snd pivot), 
          lookup t 6 (fst old_mapping) (snd old_mapping),
          lookup t 6 (fst new_mapping) (snd new_mapping) 
    with
    | Some new_mapping, None, Some pivot -> true
    | Some old_mapping, Some pivot, None -> true
    | _, _, _ -> false
  in
  assert_equal true (is_consistent t)

let suite = "test-lookup" >::: 
  [
    "basic lookups work" >:: basic_lookup;
    "crud" >:: crud;
    "overlapping updates preserve consistency" >:: overlapping_updates
  ]

let () = run_test_tt_main suite
