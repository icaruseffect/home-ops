#! /usr/bin/env python3
import sys

content = sys.stdin.read()
if "CLASS:PRIVATE" not in content:
    content = content.replace("SUMMARY", "CLASS:PRIVATE\nSUMMARY:")

print(content, end="")
