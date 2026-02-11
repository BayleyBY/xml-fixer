 import os
import re
import xml.etree.ElementTree as ET

def clean_xmls(root_dir):
    """
    Recursively scans for XML files (excluding existing _cleaned.xml files).
    Filters clipitems: Keeps only files starting with 'A_' or 'BRT_0021.mov'.
    Fixes Reel metadata for 'A_' files if missing.
    Saves output as [original_name]_cleaned.xml.
    """
    
    xml_count = 0
    cleaned_count = 0
    
    print(f"Scanning directory: {root_dir}")

    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            # Process only .xml files, skip already cleaned ones
            if filename.lower().endswith('.xml') and not filename.lower().endswith('_cleaned.xml'):
                xml_count += 1
                file_path = os.path.join(dirpath, filename)
                output_path = os.path.join(dirpath, os.path.splitext(filename)[0] + "_cleaned.xml")
                
                print(f"Processing: {filename}")
                
                try:
                    # Parse XML
                    tree = ET.parse(file_path)
                    root = tree.getroot()
                    
                    removed_clips = 0
                    fixed_metadata = 0
                    
                    # 1. Build a map of file_id -> filename
                    # Search ALL file elements in the document
                    file_map = {}
                    for file_elem in root.iter('file'):
                        f_id = file_elem.get('id')
                        name_elem = file_elem.find('name')
                        if f_id and name_elem is not None and name_elem.text:
                            file_map[f_id] = name_elem.text
                    
                    # Iterate through sequence/media/video and sequence/media/audio tracks
                    # Structure: xmeml -> sequence -> media -> video/audio -> track -> clipitem
                    
                    for sequence in root.findall('sequence'):
                        media = sequence.find('media')
                        if media is None:
                            continue
                            
                        # 2. Process Audio Tracks - PURGE ALL
                        audio_section = media.find('audio')
                        if audio_section is not None:
                            # Remove all tracks from audio section
                            # We iterate a copy of list to modify safely
                            for track in list(audio_section.findall('track')):
                                audio_section.remove(track)
                            # print("   Purged all audio tracks.")

                        # 3. Process Video Tracks
                        video_section = media.find('video')
                        if video_section is not None:
                            # Iterate over video tracks
                            # We iterate a copy to allow removing the track itself if it becomes empty
                            for track in list(video_section.findall('track')):
                                # Find all clipitems to remove or modify
                                # We iterate a copy of list to modify original list safely
                                for clipitem in track.findall('clipitem'):
                                    file_node = clipitem.find('file')
                                    should_keep = False
                                    file_name_text = ""
                                    
                                    # If it has a file node, check the name
                                    if file_node is not None:
                                        # Try to find name directly
                                        name_node = file_node.find('name')
                                        if name_node is not None and name_node.text:
                                            file_name_text = name_node.text
                                        else:
                                            # Try to resolve via ID
                                            f_id = file_node.get('id')
                                            if f_id in file_map:
                                                file_name_text = file_map[f_id]
                                        
                                        if file_name_text:
                                            if file_name_text.startswith('A_') or file_name_text == 'BRT_0021.mov':
                                                 should_keep = True
                                    
                                    if not should_keep:
                                        # Remove this clipitem
                                        track.remove(clipitem)
                                        removed_clips += 1
                                    else:
                                        # It is a keeper. Logic handled in post-processing.
                                        pass
                                
                                # Check if track is empty after cleaning
                                # If no clipitems left, remove the track
                                if len(track.findall('clipitem')) == 0:
                                    video_section.remove(track)
                                    # print("   Removed empty video track.") 

                    # 3. Post-process metadata for ALL kept files (using the map/iter again or just doing it once)
                    # Unique processing per file ID to avoid double work
                    processed_file_ids = set()
                    
                    # Re-scan to fix metadata on the DEFINITIONS
                    for file_elem in root.iter('file'):
                        f_id = file_elem.get('id')
                        if not f_id or f_id in processed_file_ids:
                            continue
                            
                        name_elem = file_elem.find('name')
                        if name_elem is not None and name_elem.text:
                            fname = name_elem.text
                            if fname.startswith('A_'):
                                # Check/Fix Metadata
                                timecode_node = file_elem.find('timecode')
                                if timecode_node is not None:
                                    reel_node = timecode_node.find('reel')
                                    if reel_node is None:
                                        match = re.search(r'(A_\d+).*_h([A-Z0-9]{4})', fname)
                                        if match:
                                            reel_name_str = f"{match.group(1)}_{match.group(2)}"
                                            new_reel = ET.Element('reel')
                                            new_reel_name = ET.SubElement(new_reel, 'name')
                                            new_reel_name.text = reel_name_str
                                            timecode_node.append(new_reel)
                                            fixed_metadata += 1
                                processed_file_ids.add(f_id)

                    # Save the cleaned XML
                    # Use UTF-8 and include XML declaration (although ET might differ slightly in format from FCP XML)
                    # We might need to preserve DOCTYPE manually or just standard XML write
                    
                    if removed_clips > 0 or fixed_metadata > 0:
                        tree.write(output_path, encoding='UTF-8', xml_declaration=True)
                        print(f" -> Saved to {os.path.basename(output_path)}")
                        print(f"    Removed {removed_clips} clips. Fixed metadata for {fixed_metadata} clips.")
                        cleaned_count += 1
                    else:
                        print(f" -> No changes needed for {filename}")

                except Exception as e:
                    print(f"Error processing {filename}: {e}")

    print(f"\nSummary:")
    print(f"Scanned {xml_count} XML files.")
    print(f"Cleaned {cleaned_count} files.")

if __name__ == "__main__":
    import sys
    
     # Check if a directory path is provided as an argument
    if len(sys.argv) > 1:
        target_directory = sys.argv[1]
    else:
        # Use the current directory where the script is located
        target_directory = os.path.dirname(os.path.abspath(__file__))
    
    print(f"This script will CLEAN XML files in: {target_directory}")
    
    # Check if run non-interactively
    if not sys.stdin.isatty():
        confirmation = 'yes'
    else:
        confirmation = input("Type 'yes' to proceed: ")
    
    if confirmation.lower() == 'yes':
        clean_xmls(target_directory)
    else:
        print("Operation cancelled.")
