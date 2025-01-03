#--------------------------------------------------------
# Makefile for Synthesis, Simulation, Logs, and File Collection
# This Makefile handles multiple targets:
# - `synthesis` for synthesizing design to Synopsys 32-nm Cell Library
# - `run` for running simulations
# - `log` for viewing log files
# - `collect` for collecting design and test files
# - `clean` for cleaning up the directories
#--------------------------------------------------------

# Handle different goals (run, log, collect, synthesis) by parsing arguments passed to make.
ifeq ($(firstword $(MAKECMDGOALS)), run)
  runargs := $(wordlist 2, $(words $(MAKECMDGOALS)), $(MAKECMDGOALS))
  # Create dummy targets for each argument to prevent make from interpreting them as file targets.
  $(eval $(runargs):;@true)
else ifeq ($(firstword $(MAKECMDGOALS)), log)
  logargs := $(wordlist 2, $(words $(MAKECMDGOALS)), $(MAKECMDGOALS))
 # Create dummy targets for each argument to prevent make from interpreting them as file targets.
  $(eval $(logargs):;@true)
else ifeq ($(firstword $(MAKECMDGOALS)), collect)
  collectargs := $(wordlist 2, $(words $(MAKECMDGOALS)), $(MAKECMDGOALS))
  # Create dummy targets for each argument to prevent make from interpreting them as file targets.
  $(eval $(collectargs):;@true)
endif

# Define test number mappings to subdirectories.
simple_tests := 0 1
move_tests := 2 3 4 5 6 7 8 9 10 11 12 13 14
logic_tests := 15 16 17 18 19 20 21 22 23 24 25 26 27 28

# Declare the `synthesis`, `run`, `log`, `collect`, and `clean` targets as phony to avoid conflicts.
.PHONY: synthesis run log collect clean

#--------------------------------------------------------
# Default Synthesis Target
# Runs the Design Compiler script to perform RTL-to-Gate 
# synthesis, generating a .vg file (Verilog netlist) and
# a .sdc file (timing constraints). The synthesis process
# will only run if the .dc script changes, ensuring efficient 
# execution by avoiding redundant runs.
#
# Usage:
#   make synthesis - Executes synthesis if the .vg
#                    file is missing or if the .dc script 
#                    has been modified.
#--------------------------------------------------------

# Top-level synthesis target: Ensures the required output files
# are generated by running the Design Compiler script.
synthesis: ./designs/post_synthesis/KnightsTour.vg

# Dependency rule for generating the .vg file:
# If the .dc script changes, the Design Compiler will be invoked
# to regenerate these files.
./designs/post_synthesis/KnightsTour.vg: ./scripts/KnightsTour.dc
	@echo "Synthesizing KnightsTour to Synopsys 32-nm Cell Library..."
	@mkdir -p ./synthesis
	@mkdir -p ./designs/post_synthesis
	@mkdir -p ./output/logs/compilation
	@mkdir -p ./output/logs/transcript/reports/
	@cd ./synthesis && echo "source ../scripts/KnightsTour.dc; report_register -level_sensitive; check_design; exit;" | dc_shell -no_gui > ../output/logs/compilation/synth_compilation.log 2>&1
	@echo "Synthesis complete. Run 'make log c s' for details."

#--------------------------------------------------------
# Run Target
# Executes test cases based on the provided mode and arguments.
#
# Usage:
#   make run                        - Runs all tests in default mode.
#   make run <test_number>          - Runs a specific test by number.
#   make run <test_range>           - Runs a range of tests.
#   make run v <args>               - View waveforms in GUI mode.
#   make run g <args>               - Run tests in GUI mode.
#   make run s <args>               - Run tests and save waveforms.
#
# Arguments:
#   v - View waveforms in GUI mode.
#   g - Run tests in GUI mode.
#   s - Run tests and save waveforms.
#   <test_number> - The number of the test to execute.
#   <test_range>  - A range of tests to execute, e.g., 1-10.
#
# Description:
# This target determines the behavior based on the number and type of
# arguments passed (`runargs`). It invokes a Python script with the
# appropriate mode flags:
#   - Mode 0: Default mode.
#   - Mode 1: Save waveforms.
#   - Mode 2: GUI mode.
#   - Mode 3: View waveforms in GUI mode.
# It provides usage guidance and error handling for invalid inputs.
#--------------------------------------------------------

run:
	@if [ "$(words $(runargs))" -eq 0 ]; then \
		# No arguments: Default behavior. \
		cd scripts && python3 run_tests.py -m 0; \
	elif [ "$(words $(runargs))" -ge 1 ]; then \
		case "$(word 1,$(runargs))" in \
		v) \
			# If 'v' is specified, view waveforms in GUI mode. \
			if [ "$(words $(runargs))" -eq 3 ]; then \
				cd scripts && python3 run_tests.py -r $(word 2,$(runargs)) $(word 3,$(runargs)) -m 3; \
			elif [ "$(words $(runargs))" -eq 2 ]; then \
				cd scripts && python3 run_tests.py -n $(word 2,$(runargs)) -m 3; \
			else \
				cd scripts && python3 run_tests.py -m 3; \
			fi ;; \
		g) \
			# If 'g' is specified, run tests in GUI mode. \
			if [ "$(words $(runargs))" -eq 3 ]; then \
				cd scripts && python3 run_tests.py -r $(word 2,$(runargs)) $(word 3,$(runargs)) -m 2; \
			elif [ "$(words $(runargs))" -eq 2 ]; then \
				cd scripts && python3 run_tests.py -n $(word 2,$(runargs)) -m 2; \
			else \
				cd scripts && python3 run_tests.py -m 2; \
			fi ;; \
		s) \
			# If 's' is specified, run tests and save waveforms. \
			if [ "$(words $(runargs))" -eq 3 ]; then \
				cd scripts && python3 run_tests.py -r $(word 2,$(runargs)) $(word 3,$(runargs)) -m 1; \
			elif [ "$(words $(runargs))" -eq 2 ]; then \
				cd scripts && python3 run_tests.py -n $(word 2,$(runargs)) -m 1; \
			else \
				cd scripts && python3 run_tests.py -m 1; \
			fi ;; \
		[0-9]*) \
			# Default mode (command-line mode) with test number or range. \
			if [ "$(words $(runargs))" -eq 2 ]; then \
				cd scripts && python3 run_tests.py -r $(word 1,$(runargs)) $(word 2,$(runargs)) -m 0; \
			elif [ "$(words $(runargs))" -eq 1 ]; then \
				cd scripts && python3 run_tests.py -n $(word 1,$(runargs)) -m 0; \
			else \
				echo "Error: Invalid argument combination."; \
				exit 1; \
			fi ;; \
		*) \
			# Invalid argument error. \
			echo "Error: Invalid mode or arguments. Supported modes are:"; \
			echo "  v - View waveforms in GUI mode"; \
			echo "  g - Run tests in GUI mode"; \
			echo "  s - Run tests and save waveforms"; \
			echo "  <test_number>/<test_range> - Run specific tests"; \
			exit 1 ;; \
		esac; \
	else \
		# Invalid usage: Display error and usage information. \
		echo "Error: Invalid arguments. Usage:"; \
		echo "  make run v|g|s <test_number>/<test_range>"; \
		echo "  make run <test_number>/<test_range>"; \
		exit 1; \
	fi;

#--------------------------------------------------------
# Log Target
# Displays various log files depending on the specified mode and arguments.
#
# Usage:
#   make log s <report_type>       - Displays synthesis reports based on the specified type.
#   make log c <type/number>       - Displays compilation logs based on type or test number.
#   make log t <test_number>       - Displays transcript logs for a specific test.
#
# Arguments:
#   s - For displaying synthesis-related reports:
#       a - Area report.
#       n - Min delay report.
#       x - Max delay report.
#   c - For displaying compilation logs:
#       s - Synthesis compilation log.
#       <test_number> - Compilation log for a specific test.
#   t - For displaying transcript logs for a specific test.
#
# Description:
# This target checks for different modes (`s`, `c`, `t`) and performs corresponding actions
# to display the appropriate log files based on the sub-arguments provided.
# The script will show error messages for invalid or missing arguments.
#--------------------------------------------------------

log:
	@if [ "$(words $(logargs))" -ge 1 ]; then \
		case "$(word 1,$(logargs))" in \
		s) \
			# Check for sub-arguments under 's' for different log types. \
			case "$(word 2,$(logargs))" in \
			a) \
				echo "Displaying area report:"; \
				cat ./output/logs/transcript/reports/KnightsTour_area.txt ;; \
			n) \
				echo "Displaying min delay report:"; \
				cat ./output/logs/transcript/reports/KnightsTour_min_delay.txt ;; \
			x) \
				echo "Displaying max delay report:"; \
				cat ./output/logs/transcript/reports/KnightsTour_max_delay.txt ;; \
			*) \
				echo "Error: Invalid sub-argument for 's' log type."; \
				exit 1 ;; \
			esac ;; \
		c) \
			if [ "$(words $(logargs))" -eq 2 ]; then \
				case "$(word 2,$(logargs))" in \
				s) \
					echo "Displaying synthesis compilation log:"; \
					cat ./output/logs/compilation/synth_compilation.log ;; \
				*) \
					echo "Displaying compilation log for test $(word 2,$(logargs)):"; \
					cat ./output/logs/compilation/compilation_$(word 2,$(logargs)).log ;; \
				esac; \
			else \
				echo "Error: Invalid argument for log target."; \
				exit 1; \
			fi ;; \
		t) \
			if [ "$(words $(logargs))" -eq 2 ]; then \
				echo "Displaying transcript log for test $(word 2,$(logargs)):"; \
				cat ./output/logs/transcript/KnightsTour_tb_$(word 2,$(logargs)).log; \
			else \
				echo "Error: 't' requires a test number (e.g., make log t 3)."; \
				exit 1; \
			fi ;; \
		*) \
			echo "Error: Missing or invalid arguments. Usage:"; \
			echo "  make log s <report_type>"; \
			echo "  make log c <type/number>"; \
			echo "  make log t <number>"; \
			exit 1 ;; \
		esac; \
	else \
		echo "Error: Missing argument for logs target."; \
		exit 1; \
	fi;

#--------------------------------------------------------
# Collect Target
# Collects test files or all design files based on the specified arguments.
#
# Usage:
#   make collect <start_number> <end_number> - Collects test files for a range of test numbers.
#   make collect - Collects all design files.
#
# Arguments:
#   <start_number> <end_number> - Range of test numbers (inclusive) to collect test files.
#
# Description:
# This target handles two scenarios:
# 1. Collecting test files for a specified range of test numbers (if two arguments are provided).
# 2. Collecting all design files (if no arguments are provided).
#
# For each test number in the specified range, it checks which subdirectory the test belongs to (simple, move, logic),
# and copies the corresponding test files to the target directory.
#
# If no files are found in the specified range, it will display a warning message.
#
# For the second case (no range), all design files are copied from the `pre_synthesis` folder to the target directory.
#--------------------------------------------------------

collect:
	@if [ "$(words $(collectargs))" -eq 2 ]; then \
		start=$(word 1,$(collectargs)); \
		end=$(word 2,$(collectargs)); \
		target_dir="../KnightsTour"; \
		mkdir -p $$target_dir; \
		echo "Collecting test files from $$start to test $$end..."; \
		found=0; \
		for num in $$(seq $$start $$end); do \
			# Determine the subdirectory based on test number \
			if echo "$(simple_tests)" | grep -qw $$num; then \
				subdir="simple"; \
			elif echo "$(move_tests)" | grep -qw $$num; then \
				subdir="move"; \
			elif echo "$(logic_tests)" | grep -qw $$num; then \
				subdir="logic"; \
			else \
				echo "Warning: Test number $$num is not mapped to any subdirectory. Skipping."; \
				continue; \
			fi; \
			# Path to the test file. \
			src_file="./tests/$$subdir/KnightsTour_tb_$$num.sv"; \
			# Copy the file if it exists \
			if [ -f $$src_file ]; then \
				cp $$src_file $$target_dir/; \
				found=1; \
			else \
				echo "Error: Test file $$src_file not found."; \
			fi; \
		done; \
		# If no files were found in the range, print a message. \
		if [ $$found -eq 1 ]; then \
			echo "All test files collected."; \
		else \
			echo "No test files were found for the range $$start-$$end."; \
		fi; \
	else \
		# Collect all design files if no range is provided. \
		echo "Collecting all design files..."; \
		mkdir -p ../KnightsTour; \
		cp ./designs/pre_synthesis/*.sv ../KnightsTour/; \
		echo "All design files collected."; \
	fi;

#--------------------------------------------------------
# Clean Target
# Removes all generated files and directories to start fresh.
#
# Usage:
#   make clean
#
# Description:
# This target is used to clean up the generated files and directories that are created during the build or test process.
# It removes the following directories:
# - TESTS: Contains the work libraries of compiled test files.
# - output: Contains logs and results from tests and synthesis.
# - synthesis: Contains the output from the synthesis process.
# - KnightsTour: A directory for collected files.
#
# This is typically used to ensure that the build process starts with a clean slate, removing all files that might be left over from previous runs.
#--------------------------------------------------------

clean:
	@echo "Cleaning up generated files..."
	@rm -rf TESTS/  	   # Remove the TESTS directory.
	@rm -rf output/ 	   # Remove the output directory.
	@rm -rf synthesis/     # Remove the synthesis directory.
	@rm -rf ../KnightsTour # Remove collected files.
	@echo "Cleanup complete."
