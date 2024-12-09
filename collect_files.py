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
                destination_file = os.path.join(target_dir, file)

                # Avoid overwriting files with the same name
                if os.path.exists(destination_file):
                    print(f"Warning: File {file} already exists in the target directory. Skipping.")
                    continue

                shutil.copy(source_file, destination_file)
                print(f"Copied design file: {source_file} -> {destination_file}")

def collect_test_files(test_dir, target_dir, test_range):
    """Collect a range of test files or a single test file."""
    found = False

    # Handle the range or single test
    for test_number in range(test_range[0], test_range[1] + 1):
        test_filename = f"KnightsTour_tb_{test_number}.sv"
        
        # Determine the subdirectory based on the test number using the test_mapping
        test_subfolder = None
        for subfolder, test_range_values in test_mapping.items():
            if test_number in test_range_values:
                test_subfolder = subfolder
                break
        
        if test_subfolder is None:
            print(f"Error: Test number {test_number} is out of range or invalid.")
            continue
        
        # Search for the test file within the identified subfolder
        test_subfolder_path = os.path.join(test_dir, test_subfolder)
        file_found = False

        for root, dirs, files in os.walk(test_subfolder_path):
            if test_filename in files:
                source_file = os.path.join(root, test_filename)
                destination_file = os.path.join(target_dir, test_filename)

                # Avoid overwriting files with the same name
                if os.path.exists(destination_file):
                    print(f"Warning: Test file {test_filename} already exists in the target directory. Skipping.")
                    continue

                shutil.copy(source_file, destination_file)
                print(f"Copied test file: {source_file} -> {destination_file}")
                file_found = True
                found = True
                break

        if not file_found:
            print(f"Error: Test file {test_filename} not found in {test_subfolder_path}.")

    if not found:
        print(f"No test files were found for the specified range {test_range[0]}-{test_range[1]}.")

def collect_post_synthesis_files(post_synthesis_dir, target_dir):
    """Collect all .sv files and the .vg file from the post_synthesis directory."""
    if not os.path.exists(post_synthesis_dir):
        print(f"Error: Post-synthesis directory {post_synthesis_dir} does not exist.")
        return

    if not os.path.exists(target_dir):
        os.makedirs(target_dir)

    found = False
    for root, dirs, files in os.walk(post_synthesis_dir):
        for file in files:
            if file.endswith(".sv") or file.endswith(".vg"):
                source_file = os.path.join(root, file)
                destination_file = os.path.join(target_dir, file)

                # Avoid overwriting files with the same name
                if os.path.exists(destination_file):
                    print(f"Warning: File {file} already exists in the target directory. Skipping.")
                    continue

                shutil.copy(source_file, destination_file)
                print(f"Copied post-synthesis file: {source_file} -> {destination_file}")
                found = True

    if not found:
        print(f"No .sv or .vg files were found in the post-synthesis directory.")

def main():
    parser = argparse.ArgumentParser(description="Collect Verilog files from designs, tests, and post-synthesis directories.")
    parser.add_argument(
        "target_directory",
        help="Name of the directory to create for storing collected files."
    )
    parser.add_argument(
        "-d", "--designs", action="store_true",
        help="Collect all .sv files from designs folders, excluding tests."
    )
    parser.add_argument(
        "-t", "--test", type=str,
        help="Specify a single test number or range of test numbers (e.g., 1 or 13-16)."
    )
    parser.add_argument(
        "-ps", "--post_synthesis", action="store_true",
        help="Collect all .sv files and the .vg file from the post_synthesis directory within tests."
    )
    args = parser.parse_args()

    current_dir = os.getcwd()
    source_designs_dir = os.path.join(current_dir, "designs")
    source_tests_dir = os.path.join(current_dir, "tests")
    post_synthesis_dir = os.path.join(source_tests_dir, "post_synthesis")
    target_dir = os.path.join(current_dir, "..", args.target_directory)

    # Perform actions based on the flags
    if args.designs:
        collect_design_files(source_designs_dir, target_dir)
    if args.test:
        # Parse the range or single test number from the input argument
        try:
            if '-' in args.test:
                test_range = [int(x) for x in args.test.split('-')]
                if len(test_range) == 2 and test_range[0] <= test_range[1]:
                    collect_test_files(source_tests_dir, target_dir, test_range)
                else:
                    print("Error: Invalid test range. Please provide a valid range like '13-16'.")
            else:
                # Treat single test number as a range with one file
                test_number = int(args.test)
                collect_test_files(source_tests_dir, target_dir, [test_number, test_number])
        except ValueError:
            print("Error: Test range or number must be a valid integer or range like '13-16'.")
    if args.post_synthesis:
        collect_post_synthesis_files(post_synthesis_dir, target_dir)

    if not args.designs and not args.test and not args.post_synthesis:
        print("Error: You must specify at least one of the flags: --designs (-d), --test (-t), or --post_synthesis (-ps).")

if __name__ == "__main__":
    main()
