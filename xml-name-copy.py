import os
import sys
import xml.etree.ElementTree as ET

def rename_timelines(directory, recursive=False):
    count = 0
    if recursive:
        walker = os.walk(directory)
    else:
        walker = [(directory, [], os.listdir(directory))]

    for dirpath, _, filenames in walker:
        for filename in filenames:
            if not filename.lower().endswith('.xml') or filename.lower().endswith('_renamed.xml'):
                continue

            file_path = os.path.join(dirpath, filename)
            base_name = os.path.splitext(filename)[0]

            try:
                tree = ET.parse(file_path)
                root = tree.getroot()
            except ET.ParseError as e:
                print(f"Skipping {filename}: {e}")
                continue

            changed = False
            for seq in root.iter('sequence'):
                name_elem = seq.find('name')
                if name_elem is not None:
                    name_elem.text = base_name
                    changed = True

            if changed:
                output_path = os.path.join(dirpath, base_name + "_renamed.xml")
                tree.write(output_path, encoding='UTF-8', xml_declaration=True)
                print(f"{filename} -> {os.path.basename(output_path)}")
                count += 1
            else:
                print(f"Skipping {filename}: no <sequence><name> found")

    print(f"\nRenamed {count} file(s).")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python xml-name-copy.py <folderpath> [--recursive]")
        sys.exit(1)

    folder = sys.argv[1]
    recursive = '--recursive' in sys.argv

    if not os.path.isdir(folder):
        print(f"Error: '{folder}' is not a valid directory")
        sys.exit(1)

    rename_timelines(folder, recursive)
