import os
import subprocess
import shutil
import argparse

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Run specific testbench or all testbenches in GUI or command-line mode.")
parser.add_argument(
    "-n", "--number", type=int, nargs="?", default=None,
    help="Specify the testbench number to run (e.g., 1 for test_1). If not specified, runs all tests."
)
parser.add_argument('-r', '--range', type=int, nargs=2, metavar=('START', 'END'),
                     help='Test range to run (inclusive, e.g., -r 2 10)'
)
parser.add_argument(
    "-m", "--mode", type=str, choices=["gui", "cmd"], default="cmd",
    help="Specify the mode to run the simulation: 'gui' or 'cmd'. Default is 'cmd'."
)
parser.add_argument(
    "-d", "--debug", type=int, choices=[0, 1, 2, 3], default=0,
    help="Enable debugging mode: 0 will not enable debugging waves (if test passes), 1 will enable debugging waves for later (even if test might pass), 2 is debugging waves while running, 3 for debugging saved waves"
)
parser.add_argument(
    "-s", "--signals", type=str, nargs="*", default=None,
    help="List of custom signals to add to the waveform (e.g., clk RST_n iPHYS/xx). If not provided, default signals are used."
)
parser.add_argument("-ps", "--post_synthesis", action="store_true", help="Run post-synthesis simulation tasks.")
args = parser.parse_args()

# Directories
root_dir = os.path.abspath(os.path.dirname(__file__))  # Top-level directory (current directory)
design_dir = os.path.join(root_dir, "designs")  # Design files directory
test_dir = os.path.join(root_dir, "tests")  # Test files directory
post_synthesis_dir = os.path.join(root_dir, "tests", "post_synthesis")  # Directory for post synthesis tests
output_dir = os.path.join(root_dir, "output")  # Output directory for logs and results
transcript_dir = os.path.join(output_dir, "transcript")  # Subdirectory for log files
waves_dir = os.path.join(output_dir, "waves")  # Subdirectory for waveform files
library_dir = os.path.join(root_dir, "work")  # Simulation library directory

# Ensure output and library directories exist
os.makedirs(transcript_dir, exist_ok=True)
os.makedirs(waves_dir, exist_ok=True)
os.makedirs(library_dir, exist_ok=True)

# Mapping test numbers to subdirectories and file ranges
test_mapping = {
    "simple": range(1, 2),  # test_1
    "move": range(2, 15),   # test_2 to test_14
    "logic": range(15, 22)  # test_15 to test_21
}

# Compile all design files (ignoring `tests/` subdirectories)
for root, dirs, files in os.walk(design_dir):
    if "tests" in dirs:
        dirs.remove("tests")  # Skip the `tests` subdirectory

    for file in files:
        if file.endswith(".sv"):
            file_path = os.path.join(root, file)
            subprocess.run(f"vlog +acc {file_path}", shell=True, check=True)

# Compile shared test files
test_files = ["tb_tasks.sv", "KnightPhysics.sv", "SPI_iNEMO4.sv"]
for test_file in test_files:
    test_path = os.path.join(test_dir, test_file)
    if os.path.exists(test_path):
        subprocess.run(f"vlog +acc {test_path}", shell=True, check=True)

# Helper function to find the full hierarchy paths for signals
def find_signals(signal_names):
    """Find the full hierarchy paths for the given signal names, prioritizing full paths if specified."""
    signal_paths = []
    for signal in signal_names:
        if "/" in signal:
            signal_paths.append(signal)
            continue

        try:
            result = subprocess.run(
                f"vsim -c work.KnightsTour_tb -do \"find signals /KnightsTour_tb/{signal}* -recursive; quit;\"",
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            found_signal = False
            for part in result.stdout.split():
                if part.startswith("#") or not part.strip() or part.strip() in ["//", "-access/-debug"]:
                    continue
                if "/" in part:
                    if part.strip().split("/")[-1] == signal and not found_signal:
                        signal_paths.append(part.strip())
                        found_signal = True
        except subprocess.CalledProcessError as e:
            print(f"Error finding signal {signal}: {e.stderr}")
    return signal_paths

# Check transcript for pass or error
def check_transcript(log_file):
    """Check if the transcript contains success or error messages."""
    with open(log_file, 'r') as f:
        content = f.read()
        if "YAHOO!! All tests passed." in content:
            return "success"
        elif "ERROR" in content:
            return "error"
    return "unknown"

# Default signals if user doesn't specify custom ones
default_signals = [
    "clk", "RST_n", "iPHYS/xx", "iPHYS/yy", "heading", "heading_robot", "desired_heading", "omega_sum", 
    "iPHYS/cntrIR_n", "iDUT/iCMD/lftIR", "iDUT/iCMD/cntrIR", "iDUT/iCMD/rghtIR", "y_pos", "y_offset", 
    "came_back", "off_board", "error_abs", "iDUT/iCMD/square_cnt", "iDUT/iCMD/move_done", "iDUT/iTC/state", "send_resp", "resp", "/KnightsTour_tb/resp_rdy",
    "mv_indx", "move", "iDUT/iCMD/pulse_cnt", "iDUT/iCMD/state", "iDUT/iCMD/tour_go", "iDUT/iTL/done", "fanfare_go", "iDUT/ISPNG/state"
]

# Function to run a specific testbench
def run_testbench(subdir, test_file, mode, debug_mode):
    test_path = os.path.join(test_dir, subdir, test_file)
    test_name = os.path.splitext(test_file)[0]
    log_file = os.path.join(transcript_dir, f"{test_name}.log")
    wave_file = os.path.join(waves_dir, f"{test_name}.wlf")
    wave_format_file = os.path.join(waves_dir, f"{test_name}.do")

    if args.post_synthesis:
        # Change working directory to post_synthesis directory.
        os.chdir(post_synthesis_dir)

        sim_command = f"vsim -c -do 'project open {os.path.expanduser('~/PostSynthesis.mpf')}; " \
                      f"project compileall; vsim -gui work.KnightsTour_tb -t ns -L {os.path.expanduser('~/ece551/SAED32_lib')} " \
                      f"-Lf {os.path.expanduser('~/ece551/SAED32_lib')} -voptargs=+acc'"

        # Run post-synthesis specific steps
        subprocess.run(
            sim_command,
            shell=True,
            check=True
        )
    else:
        subprocess.run(f"vlog +acc {test_path}", shell=True, check=True)

    if debug_mode == 3:
        # Change working directory to /output/waves for debugging
        os.chdir(waves_dir)
        sim_command = f"vsim -view {test_name}.wlf -do {test_name}.do;"
        subprocess.run(sim_command, shell=True, check=True)

    else:
        # Choose whether to use default or custom signals
        if args.signals:
            signals_to_use = args.signals
        else:
            signals_to_use = default_signals

        # Find full hierarchy paths for the selected signals
        signal_paths = find_signals(signals_to_use)
        add_wave_command = " ".join([f"add wave {signal};" for signal in signal_paths])

    # Command-line mode: Run simulation, check for failure, then switch to GUI if necessary
    if mode == "cmd":
        # Base simulation command (common for all cases)
        base_command = (
            f"vsim -c -do \"vsim -wlf {wave_file} work.KnightsTour_tb; {add_wave_command} run -all; "
            f"log -flush /*; quit -f;\" > {log_file}"
        )

        if debug_mode == 0:
            # Normal run: Do not save waveforms if the test passes
            sim_command = base_command
            subprocess.run(sim_command, shell=True, check=True)

            # Check the transcript for success or error
            result = check_transcript(log_file)

            if result == "success":
                print(f"{test_name}: YAHOO!! All tests passed.")
            # Your existing conditions
            elif result == "error":
                print(f"{test_name}: Test failed. Saving waveforms for later debug...")
                # Save waveforms in case of failure
                debug_command = (
                    f"vsim -wlf {wave_file} work.KnightsTour_tb -voptargs=\"+acc\" -do \"{add_wave_command} run -all; "
                    f"write format wave -window .main_pane.wave.interior.cs.body.pw.wf {wave_format_file}; log -flush /*; quit -f;\""
                )
                subprocess.run(debug_command, shell=True, check=True)

        elif debug_mode == 1:
                # Same behavior as debug_mode 0 but always log to the file
                print(f"{test_name}: Saving waveforms and logging to file...")
                debug_command = (
                    f"vsim -wlf {wave_file} work.KnightsTour_tb -voptargs=\"+acc\" -do \"{add_wave_command} run -all; "
                    f"write format wave -window .main_pane.wave.interior.cs.body.pw.wf {wave_format_file}; "
                    f"log -flush /*; quit -f;\""
                )
                subprocess.run(debug_command, shell=True, check=True)

                # After simulation finishes, move the transcript file to the output directory and rename it.
                transcript_file = "transcript"  # ModelSim default transcript file name

                if os.path.exists(transcript_file):
                    # Move the transcript file to the output directory and rename it
                    new_log_file = os.path.join(transcript_dir, f"{test_name}.log")
                    shutil.move(transcript_file, new_log_file)
                    print(f"{test_name}: Transcript saved to {new_log_file}")
                else:
                    print(f"{test_name}: No transcript file found.")

                # Check the transcript for success or error
                result = check_transcript(new_log_file)

                if result == "success":
                    print(f"{test_name}: YAHOO!! All tests passed.")
                else:
                    print(f"{test_name}: Test failed. Debug logs saved to {log_file}.")

        elif debug_mode == 2:
                # Always save waveforms, for debugging purposes, regardless of test result.
                print(f"{test_name}: Debugging in GUI mode...")
                debug_command = (
                    f"vsim -wlf {wave_file} work.KnightsTour_tb -voptargs=\"+acc\" -do \"{add_wave_command} run -all; "
                    f"write format wave -window .main_pane.wave.interior.cs.body.pw.wf {wave_format_file}; "
                    f"log -flush /*;\""
                )
                subprocess.run(debug_command, shell=True, check=True)

                                # Define the default transcript filename generated by ModelSim

                # After simulation finishes, move the transcript file to the output directory and rename it.
                transcript_file = "transcript"  # ModelSim default transcript file name

                if os.path.exists(transcript_file):
                    # Move the transcript file to the output directory and rename it
                    new_log_file = os.path.join(transcript_dir, f"{test_name}.log")
                    shutil.move(transcript_file, new_log_file)
                    print(f"{test_name}: Transcript saved to {new_log_file}")
                else:
                    print(f"{test_name}: No transcript file found.")

    else:
            # GUI mode: Ask for custom signals, or add defaults
            print(f"{test_name}: Running tests in GUI mode...")
            debug_command = (
                    f"vsim -wlf {wave_file} work.KnightsTour_tb -voptargs=\"+acc\" -do \"{add_wave_command} run -all; "
                    f"write format wave -window .main_pane.wave.interior.cs.body.pw.wf {wave_format_file}; "
                    f"log -flush /*;\""
            )
            subprocess.run(debug_command, shell=True, check=True)
            
            # After simulation finishes, move the transcript file to the output directory and rename it.
            transcript_file = "transcript"  # ModelSim default transcript file name

            if os.path.exists(transcript_file):
                # Move the transcript file to the output directory and rename it
                new_log_file = os.path.join(transcript_dir, f"{test_name}.log")
                shutil.move(transcript_file, new_log_file)
                print(f"{test_name}: Transcript saved to {new_log_file}")
            else:
                print(f"{test_name}: No transcript file found.")
            

# Run the specified test(s) based on input arguments
if args.number:
    for subdir, test_range in test_mapping.items():
        if args.number in test_range:
            subdir_path = os.path.join(test_dir, subdir)
            test_files = [
                file
                for file in os.listdir(subdir_path)
                if file.endswith(".sv") and f"_{args.number}" in file
            ]
            for test_file in test_files:
                run_testbench(subdir, test_file, args.mode, args.debug)
            break

elif args.range:
        # Extract the start and end of the range
        start_range, end_range = args.range

        # Loop through the subdirectories and test the files within the range
        for subdir, test_range in test_mapping.items():
            subdir_path = os.path.join(test_dir, subdir)
            # Get all the test files within the directory
            test_files = [
                file
                for file in sorted(os.listdir(subdir_path))
                if file.endswith(".sv")
                and int("".join(filter(str.isdigit, file))) >= start_range
                and int("".join(filter(str.isdigit, file))) <= end_range
            ]
            
            for test_file in test_files:
                run_testbench(subdir, test_file, args.mode, args.debug)
elif args.post_synthesis:
    run_testbench("post_synthesis", "KnightsTour_tb_0.sv", args.mode, args.debug)
else:
    for subdir in ["simple", "move", "logic"]:
        subdir_path = os.path.join(test_dir, subdir)
        if os.path.exists(subdir_path):
            test_files = [
                file for file in os.listdir(subdir_path) if file.endswith(".sv")
            ]
            for file in sorted(
                test_files, key=lambda x: int("".join(filter(str.isdigit, x)))
            ):
                run_testbench(subdir, file, args.mode, args.debug)

    print("All tests completed.")
