import os
import shutil
import argparse

# Mapping test numbers to subdirectories and file ranges
test_mapping = {
    "simple": range(1, 2),  # test_1
    "move": range(2, 15),   # test_2 to test_14
    "logic": range(15, 18)  # test_15 to test_17
}

def collect_design_files(source_dir, target_dir):
    """Collect all .sv files from designs folders, excluding tests directories."""
    if not os.path.exists(target_dir):
        os.makedirs(target_dir)

    for root, dirs, files in os.walk(source_dir):
        # Ignore 'tests' directories
        dirs[:] = [d for d in dirs if d != "tests"]
        
        for file in files:
            if file.endswith(".sv"):
                source_file = os.path.join(root, file)
                # Preserve relative directory structure
                relative_path = os.path.relpath(root, source_dir)
                destination_dir = os.path.join(target_dir, relative_path)
                os.makedirs(destination_dir, exist_ok=True)
                shutil.copy(source_file, destination_dir)
                print(f"Copied design file: {source_file} -> {os.path.join(destination_dir, file)}")

def collect_test_file(test_dir, target_dir, test_number):
    """Collect a specific test file (e.g., KnightsTour_tb_<number>.sv)."""
    # Determine the subdirectory based on the test number using the test_mapping
    test_subfolder = None
    for subfolder, test_range in test_mapping.items():
        if test_number in test_range:
            test_subfolder = subfolder
            break
    
    if test_subfolder is None:
        print(f"Error: Test number {test_number} is out of range or invalid.")
        return
    
    # Build the filename based on the test number
    test_filename = f"KnightsTour_tb_{test_number}.sv"
    
    # Search for the test file within the identified subfolder
    test_subfolder_path = os.path.join(test_dir, test_subfolder)
    found = False

    for root, dirs, files in os.walk(test_subfolder_path):
        if test_filename in files:
            source_file = os.path.join(root, test_filename)
            if not os.path.exists(target_dir):
                os.makedirs(target_dir)
            shutil.copy(source_file, target_dir)
            print(f"Copied test file: {source_file} -> {os.path.join(target_dir, test_filename)}")
            found = True
            break

    if not found:
        print(f"Error: Test file {test_filename} not found in {test_subfolder_path}.")

def main():
    parser = argparse.ArgumentParser(description="Collect Verilog files from designs and tests directories.")
    parser.add_argument(
        "target_directory",
        help="Name of the directory to create for storing collected files."
    )
    parser.add_argument(
        "-d", "--designs", action="store_true",
        help="Collect all .sv files from designs folders, excluding tests."
    )
    parser.add_argument(
        "-t", "--test", type=int,
        help="Specify a test number to collect (e.g., KnightsTour_tb_<number>.sv)."
    )
    args = parser.parse_args()

    current_dir = os.getcwd()
    source_designs_dir = os.path.join(current_dir, "designs")
    
    # Now, the tests are located in the tests subfolder of the 'KnightsTour' folder
    source_tests_dir = os.path.join(current_dir, "tests")
    target_dir = os.path.join(current_dir, "..", args.target_directory)

    # Perform actions based on the flags
    if args.designs:
        collect_design_files(source_designs_dir, target_dir)
    if args.test is not None:
        collect_test_file(source_tests_dir, target_dir, args.test)

    if not args.designs and args.test is None:
        print("Error: You must specify at least one of the flags: --designs (-d) or --test (-t).")

if __name__ == "__main__":
    main()
