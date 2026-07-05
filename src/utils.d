module utils;

import frontend.parser.ast : Node;

import core.stdc.stdlib : exit;
import std.exception;
import std.stdio;

T as(T)(Node v)
{
    T r = cast(T) v;
    enforce(r !is null, "Error converting type: Node to " ~ T.stringof);
    return r;
}

void cx_erro(string message)
{
    writefln("Cx Error: %s", message);
    exit(1);
}

void cx_enforce(bool cond, string message)
{
    if (cond)
        return;
    cx_erro(message);
}
