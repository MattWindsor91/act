# The Automagic Compiler Tormentor
#
# Copyright (c) 2018--2019 Matt Windsor and contributors
#
# ACT itself is licensed under the MIT License. See the LICENSE file in the
# project root for more information.
#
# ACT is based in part on code from the Herdtools7 project
# (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
# project root for more information.

import json
import typing
from dataclasses import dataclass

from act_py import litmus_id


@dataclass
class LitmusHeader:
    """The bit of a Litmus test that isn't code."""

    locations: typing.Optional[typing.List[str]]
    init: typing.Optional[typing.Dict[str, int]]
    postcondition: typing.Optional[str]

    def rewrite_locals(self, rewriter: typing.Callable[[litmus_id.Lid], str]):
        if self.postcondition is not None:
            self.postcondition = litmus_id.rewrite_post_locals(
                self.postcondition, rewriter
            )


def of_dict(aux_dict: typing.Dict[str, typing.Any]) -> LitmusHeader:
    locations = aux_dict["locations"]
    init = aux_dict["init"]
    postcondition = aux_dict["postcondition"]
    return LitmusHeader(locations, init, postcondition)


def load(fp: typing.TextIO) -> LitmusHeader:
    """Loads an aux file from a file pointer.

    :param fp: The (text) file pointer from which we will load an aux file.
    :return: The resulting `Aux` object.
    """
    aux_dict: typing.Dict[str, typing.Any] = json.load(fp)
    return of_dict(aux_dict)
