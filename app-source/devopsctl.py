#!/usr/bin/env python3
import subprocess
import argparse
import os

def run(cmd):
    print("> " + " ".join(cmd))
    subprocess.check_call(cmd)

def build(image, tag):
    run(["docker", "build", "-t", f"{image}:{tag}", "."])

def push(image, tag):
    run(["docker", "push", f"{image}:{tag}"])

if __name__ == "__main__":
    p = argparse.ArgumentParser()

    p.add_argument("action", choices=["build", "push"])
    p.add_argument("--image", default=os.getenv("IMAGE", "project3-app"))
    p.add_argument("--tag", default=os.getenv("TAG", "latest"))

    args = p.parse_args()

    if args.action == "build":
        build(args.image, args.tag)
    elif args.action == "push":
        push(args.image, args.tag)
