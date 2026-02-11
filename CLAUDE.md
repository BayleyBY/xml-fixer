# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single-file Python CLI utility that batch-processes Final Cut Pro (FCP) XML files. It filters video clips by naming patterns, strips audio tracks, and repairs missing reel metadata. No external dependencies — uses only Python standard library (`xml.etree.ElementTree`, `re`, `os`).

## Running

```bash
# Process XMLs in script's directory
python3 clean_xmls.py

# Process XMLs in a specific directory
python3 clean_xmls.py /path/to/xml/files
```

Output files are written as `<original>_cleaned.xml` alongside the originals. Already-cleaned files (`*_cleaned.xml`) are skipped.

## Architecture

`clean_xmls.py` contains one main function `clean_xmls(root_directory)` with three sequential phases per XML file:

1. **Audio removal** — strips all `<track>` elements from `<audio>` sections
2. **Clip filtering** — keeps only `<clipitem>` elements whose associated filename starts with `A_` or equals `BRT_0021.mov`; removes empty tracks afterward
3. **Reel metadata repair** — for kept `A_`-prefixed files missing `<reel>` inside `<file><timecode>`, extracts a reel name from the filename pattern `A_\d+.*_h[A-Z0-9]{4}` and inserts it

Key data structures: `file_map` (dict mapping file element IDs to filenames) and `processed_file_ids` (set preventing duplicate metadata fixes across clipitems referencing the same file).

## Hardcoded Business Logic

- Clip keep-filter: filename starts with `A_` or is exactly `BRT_0021.mov` (line ~88)
- Reel name regex: `A_\d+.*_h[A-Z0-9]{4}` → output format `{A_number}_{code}` (lines ~124-126)
