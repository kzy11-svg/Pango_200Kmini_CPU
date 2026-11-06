open_project {r2_pure_shared_logic.pds}
dev_map -override_pcf false -devmap_const_prop 1 -devmap_remove_dups 1
add_constraint {training_region.pcf}
pnr -gplace_seed 7 -gplace_times 1 -groute_times 1 -place_worst_slack 1200 -enable_route_constraint_iterate -route_constraint_iterate_times 1 -route_constraint_slack 0.6 -route_constraint_max_timing_path 300 -dump_router_congestion_plot TRUE
report_timing -max_path 1000 -nworst 1 -report_exception TRUE

