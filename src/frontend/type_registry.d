module frontend.type_registry;

import frontend.type_expr;

class TypeRegistry
{
private:
    TypeExpr[string] types;

public:
    this()
    {
        // inicializa com os tipos builtin da linguagem
        types["byte"] = new TypeExprNamed("char");
        types["i8"] = new TypeExprNamed("int8_t");
        types["char"] = types["byte"];

        types["ubyte"] = new TypeExprNamed("unsigned char");
        types["u8"] = new TypeExprNamed("uint8_t");
        
        types["short"] = new TypeExprNamed("short");
        types["i16"] = new TypeExprNamed("int16_t");

        types["ushort"] = new TypeExprNamed("unsigned short");
        types["u16"] = new TypeExprNamed("uint16_t");
        
        types["int"] = new TypeExprNamed("int");
        types["i32"] = new TypeExprNamed("int32_t");
        
        types["uint"] = new TypeExprNamed("unsigned int");
        types["u32"] = new TypeExprNamed("uint32_t");
        
        types["long"] = new TypeExprNamed("long");
        types["c_long"] = new TypeExprNamed("long");
        types["i64"] = new TypeExprNamed("int64_t");
        
        types["ulong"] = new TypeExprNamed("unsigned long");
        types["c_ulong"] = new TypeExprNamed("unsigned long");
        types["u64"] = new TypeExprNamed("uint64_t");
        
        types["size_t"] = new TypeExprNamed("size_t");
        
        types["float"] = new TypeExprNamed("float");
        types["f32"] = new TypeExprNamed("float");
        
        types["double"] = new TypeExprNamed("double");
        types["f64"] = new TypeExprNamed("double");
        
        types["bool"] = new TypeExprNamed("int");
        types["i1"] = new TypeExprNamed("int32_t");
        
        types["void"] = new TypeExprNamed("void");
        types["i0"] = new TypeExprNamed("void");
        
        types["cstr"] = new TypeExprPointer(types["char"]);
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
