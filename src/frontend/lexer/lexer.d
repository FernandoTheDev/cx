module frontend.lexer.lexer;

import frontend.type_registry;
import frontend.lexer.token;
import frontend.type_expr;
import errors;

import std.array : Appender;
import std.math : pow;
import std.exception;
import std.format;
import std.stdio;
import std.conv;

alias Tokens = Appender!(Token[]);
alias String = Appender!(string);

class Lexer
{
private:
    Diagnostics err;
    TypeRegistry type;
    Tokens tokens;
    string filename, source, dir;
    uint offset, loffset;
    uint line = 1;

    TokenKind[string] keywords = [
        "register": TokenKind.Register,
        "_Atomic": TokenKind.Atomic,
        "restrict": TokenKind.Restrict,
        "volatile": TokenKind.Volatile,
        "const": TokenKind.Const,
        "return": TokenKind.Return,
        "static": TokenKind.Static,
        "inline": TokenKind.Inline,
        "overload": TokenKind.Overload,
        "struct": TokenKind.Struct,
        "alias": TokenKind.Alias,
        "enum": TokenKind.Enum,
        "union": TokenKind.Union,
        "defer": TokenKind.Defer,
        "if": TokenKind.If,
        "else": TokenKind.Else,
        "for": TokenKind.For,
        "while": TokenKind.While,
        "goto": TokenKind.Goto,
        "import": TokenKind.Import,
        "continue": TokenKind.Continue,
        "break": TokenKind.Break,
        "sizeof": TokenKind.SizeOf,
        "true": TokenKind.True,
        "false": TokenKind.False,
        "null": TokenKind.Null,
        "NULL": TokenKind.Null,
    ];

    TokenKind[string] symbols = [
        "(": TokenKind.LParen,
        ")": TokenKind.RParen,
        "{": TokenKind.LBrace,
        "}": TokenKind.RBrace,
        "[": TokenKind.LBracket,
        "]": TokenKind.RBracket,
        "...": TokenKind.Ellipsis,

        ",": TokenKind.Comma,
        ":": TokenKind.Colon,
        ";": TokenKind.SemiColon,
        ".": TokenKind.Dot,
        "@": TokenKind.At,

        "+": TokenKind.Plus,
        "++": TokenKind.PPlus,
        "-": TokenKind.Minus,
        "--": TokenKind.MMinus,
        "*": TokenKind.Star,
        "/": TokenKind.Slash,
        "%": TokenKind.Modulo,

        "=>": TokenKind.Arrow,
        "==": TokenKind.EEquals,
        "===": TokenKind.EEEquals,
        "<": TokenKind.LThan,
        ">": TokenKind.GThan,
        "<=": TokenKind.LEquals,
        ">=": TokenKind.GEquals,
        "!": TokenKind.Bang,
        "!=": TokenKind.NEquals,
        "&&": TokenKind.And,
        "||": TokenKind.Or,
        "?": TokenKind.Question,

        "+=": TokenKind.PLUSEquals,
        "-=": TokenKind.MINUSEquals,
        "/=": TokenKind.DIVEquals,
        "*=": TokenKind.STAREquals,
        "%=": TokenKind.MODEquals,
        "|=": TokenKind.OBWEquals,
        "&=": TokenKind.EBWEquals,
        "<<=": TokenKind.SHLEquals,
        ">>=": TokenKind.SHREquals,
        "=": TokenKind.Equals,

        "<<": TokenKind.BITLeft,
        ">>": TokenKind.BITRight,
        "&": TokenKind.BITAnd,
        "|": TokenKind.BITOr,
        "~": TokenKind.BITNot,
        "^": TokenKind.BITXor,
    ];

    pragma(inline, true)
    bool isAtEnd(uint i = 0)
    {
        return (offset + i) >= source.length;
    }

    pragma(inline, true)
    void checkIsAtEnd(uint i = 0)
    {
        enforce(!isAtEnd(i), "Source out of bounds.");
    }

    pragma(inline, true)
    char peek()
    {
        checkIsAtEnd();
        return source[offset];
    }

    pragma(inline, true)
    char advance()
    {
        checkIsAtEnd();
        loffset++;
        return source[offset++];
    }

    pragma(inline, true)
    char previous()
    {
        loffset--;
        return source[offset--];
    }

    pragma(inline, true)
    char future(uint i)
    {
        checkIsAtEnd(i);
        return source[offset + i];
    }

    pragma(inline, true)
    bool match(char ch)
    {
        if (check(ch))
        {
            advance();
            return true;
        }
        return false;
    }

    pragma(inline, true)
    bool checkNewLine(char ch)
    {
        version (Windows)
        {
            if (ch == '\r' && !isAtEnd())
            {
                if (check('\n'))
                {
                    // o \r ja chegou com um advance()
                    advance(); // pula \n
                    loffset = 0;
                    line++;
                    return true;        
                }
            }
            return false;
        } else {
            if (ch == '\n')
            {
                loffset = 0;
                line++;
                return true;
            }
            return false;
        }
    }

    pragma(inline, true)
    bool check(char c)
    {
        return peek() == c;
    }

    pragma(inline, true)
    bool isAlpha(char c)
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    }

    pragma(inline, true)
    bool isNumeric(char c)
    {
        return c >= '0' && c <= '9';
    }

    pragma(inline, true)
    bool isAlphaNumeric(char c)
    {
        return isAlpha(c) || isNumeric(c);
    }

    pragma(inline, true)
    void pushToken(Token tk)
    {
        tokens ~= tk;
    }

    pragma(inline, true)
    Position getPos(uint s, uint l)
    {
        return new Position(dir ~ filename, dir, new LinePos(s, l), new LinePos(loffset, line));
    }

    void lexNumber(String buffer)
    {
        while (!isAtEnd() && (isNumeric(peek()) || check('_')))
            if (check('_'))
            {
                advance();
                continue;
            }
            else
                buffer ~= [advance()];
    }

    void lexDecimal(String buffer, out bool isDouble)
    {
        lexNumber(buffer);
        if (check('.'))
        {
            isDouble = true;
            buffer ~= [advance()];
            lexNumber(buffer);
        }
    }

    void lexOctal(String buffer)
    {
        while (!isAtEnd() && (peek() >= '0' && peek() <= '7'))
            buffer ~= [advance()];
    }

    void lexHex(String buffer)
    {
        while (!isAtEnd()
            && (isNumeric(peek())
                || (peek() >= 'a' && peek() <= 'f')
                || (peek() >= 'A' && peek() <= 'F')))
            buffer ~= [advance()];
    }

    char lexEscape(char ch)
    {
        if (ch != '\\')
            return ch;
        char c = advance();
        switch (c)
        {
        case 'n':
            return '\n';
        case 'r':
            return '\r';
        case 't':
            return '\t';
        case '0':
            return '\0';
        case '\\':
            return '\\';
        default:
            err.error(getPos(loffset - 1, line), "Invalid scape.");
            return ch;
        }
    }

    void lexBinary(String buffer)
    {
        while (!isAtEnd() && (peek() >= '0' && peek() <= '1'))
            buffer ~= [advance()];
    }

    void pushNumeric(string data, uint base, uint s)
    {
        try
            pushToken(Token.tk_numeric(to!long(data, base), getPos(s, line)));
        catch (Exception e)
            pushToken(Token.tk_unumeric(to!ulong(data, base), getPos(s, line)));
    }

    void lexId(ref String buffer)
    {
        while (!isAtEnd() && isAlphaNumeric(peek()))
            buffer ~= [advance()];
    }

    string lexString(uint start_o, uint start_l)
    {
        String buffer;
        buffer.reserve(32);
        
        while (!isAtEnd() && !check('"'))
        {
            checkNewLine(peek());
            buffer ~= [advance()];
        }
        
        if (!match('"'))
        {
            err.error(getPos(start_o, start_l), "The string was not closed.");
            return "/* err */";
        }

        /*
        "Str1"
        "Str2" "Str3"
        */

        skipWhiteSpace();
        string str = buffer.data;

        if (match('"'))
            return str ~= lexString(loffset, line);

        return str;
    }

    pragma(inline, true)
    void skipWhiteSpace()
    {
        while (!isAtEnd())
        {
            if (peek() == ' ' || peek() == '\r' || peek() == '\t' || checkNewLine(peek()))
            {
                advance();
                continue;
            }
            break;
        }
    }

public:
    this(string filename, string dir, string source, Diagnostics err, TypeRegistry t)
    {
        this.filename = filename;
        this.dir = dir;
        this.source = source;
        this.err = err;
        this.type = t;
    }

    Token[] tokenizer()
    {
        while (!isAtEnd())
        {
            char ch = advance();

            if (checkNewLine(ch))
                continue;

            if (ch == ' ' || ch == '\r' || ch == '\t')
                continue;

            if (isAlpha(ch))
            {
                uint start_o = loffset;
                uint l = line;
                String buffer;
                buffer.reserve(32);
                TokenKind kind = TokenKind.Id;

                buffer ~= [ch];
                lexId(buffer);

                if (buffer.data == "include")
                {
                    kind = TokenKind.Include;
                    while (!isAtEnd() && !check('\n'))
                        buffer ~= [advance()];
                }

                bool isStruct = buffer.data == "struct";
                bool isUnion = buffer.data == "union";
                bool isEnum = buffer.data == "enum";
                bool isAlias = buffer.data == "alias";
                bool isRaw = buffer.data == "__raw";

                if (isRaw)
                {
                    skipWhiteSpace();
                    int closes = 1;

                    if (!match('{'))
                    {
                        err.error(getPos(loffset, line), "Expected '{' after 'raw'.");
                        continue;
                    }

                    String raw;
                    raw.reserve(64);

                    while (!isAtEnd())
                    {
                        ch = advance();
                        if (ch == '{')
                            closes++;
                        else if (ch == '}')
                            closes--;
                        if (closes == 0)
                            break;
                        raw ~= [ch];
                    }

                    // skipWhiteSpace();
                    // advance();

                    pushToken(Token.tk_string(TokenKind.Raw, raw.data, getPos(start_o, l)));
                    continue;
                }

                if (isEnum || isStruct || isUnion || isAlias)
                {
                    kind = TokenKind.Struct;
                    if (isEnum)
                        kind = TokenKind.Enum;
                    else if (isUnion)
                        kind = TokenKind.Union;
                    else if (isAlias)
                        kind = TokenKind.Alias;
                    pushToken(Token.tk_string(kind, buffer.data, getPos(start_o, line)));

                    advance();
                    start_o = loffset + 1;
                    String name;
                    lexId(name);
                    Position pos = getPos(start_o, line);

                    TypeExprKind k = TypeExprKind.Struct;
                    if (isUnion)
                        k = TypeExprKind.Union;
                    else if (isEnum)
                        k = TypeExprKind.Enum;

                    TypeExpr t = new TypeExprUser(k, name.data, pos);
                    type.set(name.data, t);

                    pushToken(Token.tk_string(TokenKind.Id, name.data, pos));
                    continue;
                }

                if (TokenKind* k = buffer.data in keywords)
                    kind = *k;

                pushToken(Token.tk_string(kind, buffer.data, getPos(start_o, line)));
                continue;
            }

            if (isNumeric(ch))
            {
                uint start_o = loffset;

                String coe;
                coe.reserve(12);

                // 18.446.744.073.709.551.615 (máximo = 20)
                String buffer;
                buffer.reserve(20);

                bool isFloat, isDouble, isHex, isBinary, isOctal, isCientific, coeIsDouble, isUlong;

                if (ch == '0')
                {
                    switch (peek())
                    {
                    case 'x':
                        isHex = true;
                        advance();
                        break;
                    case 'b':
                        isBinary = true;
                        advance();
                        break;
                    case 'o':
                        isOctal = true;
                        advance();
                        break;
                    default:
                        break;
                    }
                }

                if (!isHex && !isBinary && !isOctal)
                    buffer ~= [ch];

                if (isOctal)
                    lexOctal(buffer);
                else if (isHex)
                    lexHex(buffer);
                else if (isBinary)
                    lexBinary(buffer);
                else
                {
                    lexDecimal(buffer, isDouble);
                    isFloat = match('F') || match('f');

                    if (match('e') || match('E'))
                    {
                        // notação cientifica
                        isCientific = true;
                        lexDecimal(coe, coeIsDouble);
                    }
                }

                string data = buffer.data();

                if (isCientific)
                {
                    // TODO: suportar sinais na notação cientifica (+ e -)
                    double result = to!double(data);
                    if (coeIsDouble)
                        result = to!double(coe.data) * pow(10.0, result);
                    else
                        result = to!long(coe.data) * pow(10.0, result);
                    pushToken(Token.tk_double(result, getPos(start_o, line)));
                    continue;
                }

                if (isFloat)
                {
                    pushToken(Token.tk_float(to!float(data), getPos(start_o, line)));
                    continue;
                }

                if (isDouble)
                {
                    pushToken(Token.tk_double(to!double(data), getPos(start_o, line)));
                    continue;
                }

                if (isHex)
                    pushNumeric(data, 16, start_o);
                else if (isOctal)
                    pushNumeric(data, 8, start_o);
                else if (isBinary)
                    pushNumeric(data, 2, start_o);
                else
                    pushNumeric(data, 10, start_o);

                continue;
            }

            if (ch == '"')
            {
                uint start_o = loffset;
                uint start_l = line;
                pushToken(Token.tk_string(TokenKind.String, lexString(start_o, start_l), getPos(start_o, start_l)));
                continue;
            }

            if (ch == '\'')
            {
                char buffer = lexEscape(advance());
                if (!match('\''))
                {
                    err.error(getPos(loffset - 1, line), "The character was not closed.");
                    continue;
                }

                // guarda como string
                pushToken(Token.tk_string(TokenKind.Char, [buffer], getPos(loffset - 1, line)));
                continue;
            }

            TokenKind k = TokenKind.Eof;
            uint size;

            if ([ch, peek()] == "//")
            {
                while (!isAtEnd() && !check('\n'))
                    advance();
                continue;
            }

            if (!isAtEnd(1))
                if (TokenKind* kk = [ch, peek(), future(1)] in symbols)
                {
                    k = *kk;
                    advance();
                    advance();
                    size++;
                    goto end;
                }
            
            if (TokenKind* kk = [ch, peek()] in symbols)
            {
                k = *kk;
                advance();
                size++;
                goto end;
            }
            
            if (TokenKind* kk = [ch] in symbols)
            {
                k = *kk;
                goto end;
            }

            err.error(getPos(loffset - size, line), format("Unkwnown char: %c", ch));
            continue;
        end:
            pushToken(Token.tk(k, getPos(loffset - size, line)));
        }
        pushToken(Token.tk(TokenKind.Eof, Position.init));
        return tokens.data();
    }
}
