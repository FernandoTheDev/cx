module frontend.type_registry;

import frontend.type_expr;
import main : noHeader;

class TypeRegistry
{
private:
    TypeExpr[string] types;

public:
    this()
    {
        // inicializa com os tipos builtin da linguagem
        types["byte"] = new TypeExprNamed("char");
        types["char"] = types["byte"];
        types["ubyte"] = new TypeExprNamed("unsigned char");
        types["short"] = new TypeExprNamed("short");
        types["ushort"] = new TypeExprNamed("unsigned short");
        types["int"] = new TypeExprNamed("int");
        types["uint"] = new TypeExprNamed("unsigned int");
        types["long"] = new TypeExprNamed("long");
        types["c_long"] = new TypeExprNamed("long");
        types["ulong"] = new TypeExprNamed("unsigned long");
        types["c_ulong"] = new TypeExprNamed("unsigned long");
        types["size_t"] = new TypeExprNamed("size_t");
        types["float"] = new TypeExprNamed("float");
        types["f32"] = new TypeExprNamed("float");
        types["double"] = new TypeExprNamed("double");
        types["f64"] = new TypeExprNamed("double");
        types["bool"] = new TypeExprNamed("int");
        types["void"] = new TypeExprNamed("void");
        types["cstr"] = new TypeExprPointer(types["char"]);
        types["volatile"] = new TypeExprNamed("volatile");
        types["const"] = new TypeExprNamed("const");
        types["_Atomic"] = new TypeExprNamed("_Atomic");
        types["restrict"] = new TypeExprNamed("restrict");
        
        if (!noHeader)
        {
            types["i8"] = new TypeExprNamed("int8_t");
            types["int8_t"] = types["i8"];
            
            types["u8"] = new TypeExprNamed("uint8_t");
            types["uint8_t"] = types["u8"];
            
            types["i16"] = new TypeExprNamed("int16_t");
            types["int16_t"] = types["i16"];
            
            types["u16"] = new TypeExprNamed("uint16_t");
            types["uint16_t"] = types["u16"];
            
            types["i32"] = new TypeExprNamed("int32_t");
            types["int32_t"] = types["i32"];
            
            types["u32"] = new TypeExprNamed("uint32_t");
            types["uint32_t"] = types["u32"];
            
            types["i64"] = new TypeExprNamed("int64_t");
            types["int64_t"] = types["i64"];
            
            types["u64"] = new TypeExprNamed("uint64_t");
            types["uint64_t"] = types["u64"];
            
            types["i1"] = new TypeExprNamed("bool");
            types["bool"] = types["i1"];
            
            types["i0"] = new TypeExprNamed("void");
            types["void"] = types["i0"];
        }
    }

    TypeExpr* get(string name)
    {
        return name in types;
    }

    bool exists(string name)
    {
        return get(name) !is null;
    }

    void update(string name, TypeExpr type)
    {
        types[name] = type;
    }

    bool set(string name, TypeExpr type)
    {
        if (name in types)
            return false;
        types[name] = type;
        return true;
    }

    bool remove(string name)
    {
        if (name !in types)
            return false;
        types.remove(name);
        return true;
    }
}
