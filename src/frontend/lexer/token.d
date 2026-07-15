module frontend.lexer.token;

import std.stdio, std.format;

enum TokenKind : ubyte
{
    // C features
    Include,

    // keywords
    Is,
    Type,
    TypeName,
    Case,
    Default,
    Switch,
    Register,
    Raw,
    Atomic,
    Restrict,
    Const,
    Volatile,
    Inline,
    Overload,
    Import,
    Goto,
    Alias,
    SizeOf,
    Enum,
    Union,
    Continue,
    Break,
    If,
    Else,
    For,
    While,
    Defer,
    Static,
    Struct,
    Return,
    
    // literals
    Id,
    String,
    Char,
    Numeric,
    UNumeric,
    Float,
    Double,
    Null,
    True,
    False,

    // symbols
    LParen, // (
    RParen, // )
    LBrace, // {
    RBrace, // }
    LBracket, // [
    RBracket, // ]

    Comma, // ,
    Colon, // :
    SemiColon, // ;
    Dot, // .
    At, // @
    Ellipsis, // ...

    Plus, // +
    PPlus, // ++
    Minus, // -
    MMinus, // -- 
    Star, // *
    Slash, // /
    Modulo, // %

    PLUSEquals, // +=
    MINUSEquals, // -=
    DIVEquals, // /=
    STAREquals, // *=
    MODEquals, // %=
    OBWEquals, // |=
    EBWEquals, // &=
    SHLEquals, // <<=
    SHREquals, // >>=
    Equals, // =


    Arrow, // =>
    EEquals, // ==
    EEEquals, // ===
    LThan, // <
    GThan, // >
    LEquals, // <=
    GEquals, // >=
    Bang, // !
    NEquals, // !=
    And, // &&
    Or, // ||
    Question, // ?

    BITLeft, // <<
    BITRight, // >>
    BITAnd, // &
    BITOr, // |
    BITNot, // ~
    BITXor, // ^

    // eof
    Eof,
}

class LinePos
{
    uint offset, line;
    this(uint offset, uint line)
    {
        this.offset = offset;
        this.line = line;
    }
}

class Position
{
    string filename, dir;
    LinePos start, end;

    this(string filename, string dir, LinePos start, LinePos end)
    {
        this.filename = filename;
        this.dir = dir;
        this.start = start;
        this.end = end;
    }

    override string toString() const
    {
        return format("%s:%d:%d", filename, start.line, start.offset);
    }
}

class Token {
    TokenKind kind;
    union {
        float f;
        long l;
        ulong u;
        double d;
        string s;
    }
    Position pos;
    this(TokenKind kind, Position pos)
    {
        this.kind = kind;
        this.pos = pos;
    }

    static Token tk_unumeric(ulong val, Position pos)
    {
        Token t = new Token(TokenKind.UNumeric, pos);
        t.u = val;
        return t;
    }

    static Token tk_numeric(long val, Position pos)
    {
        Token t = new Token(TokenKind.Numeric, pos);
        t.l = val;
        return t;
    }

    static Token tk_float(float val, Position pos)
    {
        Token t = new Token(TokenKind.Float, pos);
        t.f = val;
        return t;
    }

    static Token tk_double(double val, Position pos)
    {
        Token t = new Token(TokenKind.Double, pos);
        t.d = val;
        return t;
    }

    static Token tk_string(TokenKind kind, string val, Position pos)
    {
        Token t = new Token(kind, pos);
        t.s = val;
        return t;
    }

    static Token tk(TokenKind kind, Position pos)
    {
        return new Token(kind, pos);
    }

    void print()
    {
        writefln("TokenKind: %s\nPos: %s", kind, pos);
    }
}
