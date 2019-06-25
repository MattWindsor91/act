#!/usr/bin/env python3

import argparse

import act_py.args
import act_py.auxfile


def label_of_id(id: int) -> str:
    return f"P{id}"


def output_thread(id: int):
    print(label_of_id(id), ":", sep="")
    print("\tmfence")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(parents=[act_py.args.aux_in_parser])
    args = parser.parse_args()

    aux: act_py.auxfile.Aux = act_py.auxfile.load_path(args.aux)

    for i in range(aux.num_threads):
        output_thread(i)
