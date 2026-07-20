module utils;

import frontend.parser.ast : Node;
import frontend.type_expr;

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

string ext(string file)
{
    return (file[$ - 3 .. $] != ".cx") ? file ~ ".cx" : file;
}

string clearNameMangling(string name)
{
    string buff;
    for (ulong i; i < name.length; i++)
        if (name[i] == '*')
            buff ~= 'P';
        else
            buff ~= name[i];
    return buff;
}

bool isStruct(TypeExpr type)
{
    if (TypeExprUser p = cast(TypeExprUser) type)
        return p.kind == TypeExprKind.Struct;
    if (TypeExprGeneric p = cast(TypeExprGeneric) type)
        return true;
    return false;
}
