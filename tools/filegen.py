import os
import sys
from pathlib import Path

def scan_directory(directory_path):
    files = []
    folder_name = Path(directory_path).name
    base_path = Path(directory_path).resolve()

    for root, dirs, filenames in os.walk(base_path):
        for filename in filenames:
            full_path = Path(root) / filename
            relative_path = full_path.relative_to(base_path)
            path_str = str(relative_path).replace('\\', '/')
            full_source = f"{folder_name}/{path_str}"

            files.append({
                "source": full_source,
                "destination": full_source
            })

    return files

def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "."
    files = scan_directory(f"../{directory}")
    files.sort(key=lambda x: x["source"])

    output = "[\n"
    for i, file in enumerate(files):
        output += f'    {{"source": "{file["source"]}", "destination": "{file["destination"]}"}}'
        if i < len(files) - 1:
            output += ","
        output += "\n"
    output += "]"

    with open("./data/files.json", "w") as f:
        f.write(output)

if __name__ == "__main__":
    main()
