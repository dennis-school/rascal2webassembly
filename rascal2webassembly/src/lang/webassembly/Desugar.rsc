module lang::webassembly::Desugar

import lang::webassembly::Syntax;
import lang::webassembly::util::String2UTF8;

import ParseTree;
import List;
import util::Math;

//
// Desugars a parse tree, conforming to the concrete syntax, into a parse tree
// that conforms to a more restrictive syntax by applying desugaring rules.
//
// Public functions:
//  - start[WebAssembly] desugar( start[WebAssembly] )
//

// Many of the desugaring clauses cannot be resolved with the visit structure
//   as in many cases a sub-ADT has to be replaced by a sub-ADT of a different
//   type. Hence, these trees have to be constructed manually.
//   (e.g. a Instr beeing replaced by Instrs, containing several Instr nodes)

public start[WebAssembly] desugar( (start[WebAssembly])`<ModuleField* fields>` ) = desugar( (start[WebAssembly])`(module <ModuleField* fields>)` );

// TODO: Currently all types are registered while modifying the tree
//       Perhaps it would be better to register the types ahead of time
//       and then desugar the rest. For now, this works.
public start[WebAssembly] desugar( (start[WebAssembly])`<Module m>` ) =
  (start[WebAssembly])`<Module m3>`
  when initialTypes := getFuncTypes( m ),
       <desc2,m1> := desugarTypeUses( moduleDesc( initialTypes, occurringIds( m ) ), m ),
       <moduleDesc(finalTypes,_), m2> := desugar( desc2, m1 ),
       newTypes := finalTypes - initialTypes,
       m3 := appendTypes( m2, newTypes );

private tuple[ModuleDesc, Module] desugarTypeUses( ModuleDesc desc, Module m ) {
  m = visit ( m ) {
  case TypeUse t: {
    <desc,t2> = desugar( desc, t );
    insert t2;
  }
  }
  return <desc,m>;
}

private Type toSyntaxField( typeDesc( list[ValType] paramValTypes, list[ValType] resultValTypes ) )
  = (Type)`(type <FuncType funcType>)`
  when params := [ (Param)`(param <ValType v>)` | v <- paramValTypes ],
       results := [ (Result)`(result <ValType v>)` | v <- resultValTypes ],
       funcType := addResults( addParams( (FuncType)`(func)`, params ), results );
  
private Module appendTypes( m:(Module)`(module <Id? id> <ModuleField* fields>)`, [] ) = m;
private Module appendTypes( (Module)`(module <Id? id> <ModuleField* fields>)`, list[TypeDesc] types )
  = appendTypes( (Module)`(module <Id? id> <ModuleField* fields> <Type tField>)`, tail( types ) )
  when tField := toSyntaxField( head( types ) );
  
// ## ValTypeDescs
// For these functions the Params/Results must already be desugared

private ValType getType( (Param)`(param <Id _> <ValType t>)` ) = t;
private ValType getType( (Param)`(param <ValType t>)` ) = t;
private ValType getType( (Result)`(result <Id _> <ValType t>)` ) = t;
private ValType getType( (Result)`(result <ValType t>)` ) = t;

private list[ValType] getTypes( list[Param] params ) = [ getType( p ) | p <- params ];
private list[ValType] getTypes( list[Result] results ) = [ getType( p ) | p <- results ];

// These datatypes are introduced to avoid functions having side-effects
// Instead, these are immutable "models" that may are brought into the
// recursion. 
private data TypeDesc = typeDesc( list[ValType] params, list[ValType] results );
private data ModuleDesc = moduleDesc( list[TypeDesc] types, set[str] ids );

private tuple[ModuleDesc,Module] desugar( ModuleDesc desc, m:(Module)`(module <Id? id>)` ) = <desc,m>;
private tuple[ModuleDesc,Module] desugar( ModuleDesc desc, (Module)`(module <Id? id> <ModuleField field> <ModuleField* fields>)` )
  = <desc3, prependFields( moduleDesFields, desField )>
  when <desc2, desField> := desugar( desc, field ),
       <desc3, moduleDesFields> := desugar( desc2, (Module)`(module <Id? id> <ModuleField* fields>)` );

// ## Functions (from Section 6.6.5)
//
// Note that for these functions the desugaring is not done on the FuncFields
//   themselves, as the Id must be known, and a single function module field can
//   be an abbreviation for several module fields
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(func <Id? id> <TypeUse typeUse> <FuncBody body>)` )
  = <desc2, [ (ModuleField)`(func <Id? id> <TypeUse desTypeUse> <FuncBody desBody>)` ]>
  when <desc2,desTypeUse> := desugar( desc, typeUse ),
       desBody := desugar( body );

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(func (export <Name name>) <FuncFields fields>)` )
  = <desc3, (ModuleField)`(export <Name name> (func <FuncIdx id>))` + desFields>
  when <desc2,id> := getFreshId( desc ),
       <desc3,desFields> := desugar( desc2, (ModuleField)`(func <Id id> <FuncFields fields>)` );
  
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(func <Id id> (export <Name name>) <FuncFields fields>)` )
  = <desc2, (ModuleField)`(export <Name name> (func <FuncIdx id>))` + desugaredFields>
  when <desc2, desugaredFields> := desugar( desc, (ModuleField)`(func <Id id> <FuncFields fields>)` );

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(func <Id? id> (import <Name modName> <Name funcName>) <TypeUse typeUse>)` )
  = desugar( desc, (ModuleField)`(import <Name modName> <Name funcName> (func <Id? id> <TypeUse typeUse>))` );

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(import <Name modName> <Name funcName> (func <Id? id> <TypeUse typeUse>))` )
  = <desc2, [ (ModuleField)`(import <Name modName> <Name funcName> (func <Id? id> <TypeUse desTypeUse>))` ]>
  when <desc2,desTypeUse> := desugar( desc, typeUse );

private FuncBody desugar( (FuncBody)`<Local* locals> <Instr* instrs>` )
  = addInstrs( addLocals( (FuncBody)``, desLocals ), desInstrs )
  when desLocals := [ x | l <- locals, x <- desugar( l ) ],
       desInstrs := [ x | i <- instrs, x <- desugar( i ) ];
       
// Instr
private list[Instr] desugar( (Instr)`<FoldedInstr foldInstr>` ) = desugar( foldInstr );
private list[Instr] desugar( (Instr)`<PlainInstr plainInstr>` ) = desugar( plainInstr );

private list[Instr] desugar( PlainInstr i ) = [(Instr)`<PlainInstr i>`];
private list[Instr] desugar( (FoldedInstr)`(<PlainInstr plainInstr> <FoldedInstr* foldInstrs>)` ) = [ x | f <- foldInstrs, x <- desugar( f ) ] + [ (Instr)`<PlainInstr plainInstr>` ];
private list[Instr] desugar( (FoldedInstr)`(block <Label l> <ResultType t> <Instr* instrs>)` ) = [ addInstrs( (Instr)`block <Label l> <ResultType t> end`, [ x | i <- instrs, x <- desugar( i ) ] ) ];
private list[Instr] desugar( (FoldedInstr)`(loop <Label l> <ResultType t> <Instr* instrs>)` ) = [ addInstrs( (Instr)`loop <Label l> <ResultType t> end`, [ x | i <- instrs, x <- desugar( i ) ] ) ];

private list[Instr] desugar( (FoldedInstr)`(if <Label l> <ResultType t> <FoldedInstr condInstr> <FoldedInstr* condInstrs> (then <Instr* thenInstrs>) (else <Instr* elseInstrs>))` )
  = desugar( condInstr ) + desugar( (FoldedInstr)`(if <Label l> <ResultType t> <FoldedInstr* condInstrs> (then <Instr* thenInstrs>) (else <Instr* elseInstrs>))` );
private list[Instr] desugar( (FoldedInstr)`(if <Label l> <ResultType t> <FoldedInstr condInstr> <FoldedInstr* condInstrs> (then <Instr* thenInstrs>))` )
  = desugar( condInstr ) + desugar( (FoldedInstr)`(if <Label l> <ResultType t> <FoldedInstr* condInstrs> (then <Instr* thenInstrs>))` );
private list[Instr] desugar( (FoldedInstr)`(if <Label l> <ResultType t> (then <Instr* thenInstrs>))` )
  = [ addThenInstrs( (Instr)`if <Label l> <ResultType t> end`, desThenInstr ) ]
  when desThenInstr := [ x | i <- thenInstrs, x <- desugar( i ) ];
private list[Instr] desugar( (FoldedInstr)`(if <Label l> <ResultType t> (then <Instr* thenInstrs>) (else <Instr* elseInstrs>))` )
  = [ addElseInstrs( addThenInstrs( (Instr)`if <Label l> <ResultType t> else end`, desThenInstr ), desElseInstr ) ]
  when desThenInstr := [ x | i <- thenInstrs, x <- desugar( i ) ],
       desElseInstr := [ x | i <- elseInstrs, x <- desugar( i ) ];

private Instr addInstrs( b:(Instr)`block <Label l> <ResultType t> <Instr* instrs> end`, [] ) = b;
private Instr addInstrs( (Instr)`block <Label l> <ResultType t> <Instr* instrs> end`, list[Instr] newInstrs )
  = addInstrs( (Instr)`block <Label l> <ResultType t> <Instr* instrs> <Instr firstInstr> end`, tail( newInstrs ) )
  when firstInstr := head( newInstrs );

private Instr addInstrs( b:(Instr)`loop <Label l> <ResultType t> <Instr* instrs> end`, [] ) = b;
private Instr addInstrs( (Instr)`loop <Label l> <ResultType t> <Instr* instrs> end`, list[Instr] newInstrs )
  = addInstrs( (Instr)`loop <Label l> <ResultType t> <Instr* instrs> <Instr firstInstr> end`, tail( newInstrs ) )
  when firstInstr := head( newInstrs );

private Instr addThenInstrs( i:(Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> else <Instr* elseInstrs> end`, [] ) = i;
private Instr addThenInstrs( (Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> else <Instr* elseInstrs> end`, list[Instr] instrs )
  = addThenInstrs( (Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> <Instr instr> else <Instr* elseInstrs> end`, tail( instrs ) )
  when instr := head( instrs );

private Instr addThenInstrs( i:(Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> end`, [] ) = i;
private Instr addThenInstrs( (Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> end`, list[Instr] instrs )
  = addThenInstrs( (Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> <Instr instr> end`, tail( instrs ) )
  when instr := head( instrs );

private Instr addElseInstrs( i:(Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> else <Instr* elseInstrs> end`, [] ) = i;
private Instr addElseInstrs( (Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> else <Instr* elseInstrs> end`, list[Instr] instrs )
  = addElseInstrs( (Instr)`if <Label l> <ResultType t> <Instr* thenInstrs> else <Instr* elseInstrs> <Instr instr> end`, tail( instrs ) )
  when instr := head( instrs );

private default list[Instr] desugar( FoldedInstr i ) = [(Instr)`<FoldedInstr i>`];
private default list[Instr] desugar( Instr i ) = [ i ];

// Local
private list[Local] desugar( l:(Local)`(local <Id id> <ValType valType>)` ) = [ l ];
private list[Local] desugar( (Local)`(local <ValType valType> <ValType* valTypes>)` ) = (Local)`(local <ValType valType>)` + desugar( (Local)`(local <ValType* valTypes>)` );
private list[Local] desugar( (Local)`(local)` ) = [];

// Type
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, m:(ModuleField)`<Type t>` ) {
  m2 = visit( m ) {
  case FuncType t => desugar( t )
  }
  return <desc,[m2]>;
}

private FuncType desugar( (FuncType)`(func <Param* ps> <Result* rs>)` )
  = addResults( addParams( (FuncType)`(func)`, desugar( ps ) ), desugar( rs ) );

// ## Tables

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(table (export <Name name>) <TableFields fields>)` )
  = <desc3, (ModuleField)`(export <Name name> (table <TableIdx id>))` + desFields>
  when <desc2,id> := getFreshId( desc ),
       <desc3,desFields> := desugar( desc2, (ModuleField)`(table <Id id> <TableFields fields>)` );
  
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(table <Id id> (export <Name name>) <TableFields fields>)` )
  = <desc2, (ModuleField)`(export <Name name> (table <TableIdx id>))` + desugaredFields>
  when <desc2, desugaredFields> := desugar( desc, (ModuleField)`(table <Id id> <TableFields fields>)` );

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(table <Id? id> (import <Name modName> <Name tableName>) <TableType tableType>)` )
  = <desc, [ (ModuleField)`(import <Name modName> <Name tableName> (table <Id? id> <TableType tableType>))` ]>;

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(table <Id id> <ElemType eType> (elem <FuncIdx* idxs>))` )
  = <desc2, (ModuleField)`(table <Id id> <U32 n> <U32 n> <ElemType eType>)` + elemFields>
  when n := parse( #U32, toString( size( [ i | i <- idxs ] ) ) ),
       <desc2,elemFields> := desugar( desc, (ModuleField)`(elem <Id id> (i32.const 0) <FuncIdx* idxs>)` );

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(table <ElemType eType> (elem <FuncIdx* idxs>))` )
  = <desc3, (ModuleField)`(table <Id id> <U32 n> <U32 n> <ElemType eType>)` + elemFields>
  when <desc2,id> := getFreshId( desc ),
       n := parse( #U32, toString( size( [ i | i <- idxs ] ) ) ),
       <desc3,elemFields> := desugar( desc2, (ModuleField)`(elem <Id id> (i32.const 0) <FuncIdx* idxs>)` );

// ## Memories
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(memory (export <Name name>) <MemFields fields>)` )
  = <desc3, (ModuleField)`(export <Name name> (memory <Id id>))` + desFields>
  when <desc2,id> := getFreshId( desc ),
       <desc3,desFields> := desugar( desc2, (ModuleField)`(memory <Id id> <MemFields fields>)` );
  
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(memory <Id id> (export <Name name>) <MemFields fields>)` )
  = <desc2, (ModuleField)`(export <Name name> (memory <Id id>))` + desFields>
  when <desc2, desFields> := desugar( desc, (ModuleField)`(memory <Id id> <MemFields fields>)` );

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(memory <Id? id> (import <Name modName> <Name globalName>) <MemType memType>)` )
  = <desc, [ (ModuleField)`(import <Name modName> <Name globalName> (memory <Id? id> <MemType memType>))` ]>;

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(memory (data <DataString b>))` )
  = desugar( desc2, (ModuleField)`(memory <Id id> (data <DataString b>))` )
  when <desc2,id> := getFreshId( desc );
       
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(memory <Id id> (data <DataString b>))` )
  = <desc2, [ (ModuleField)`(memory <Id id> <U32 m> <U32 m>)` ] + desDataField >
  when m := parse( #U32, toString( ceil( len( b ) / ( 64 * 1024.0 ) ) ) ),
       <desc2,desDataField> := desugar( desc, (ModuleField)`(data <Id id> (i32.const 0) <DataString b>)` );

private int len( (DataString)`<String* s>` ) = sum( [ 0 ] + [ len( x ) | x <- s ] );
private int len( String s ) = wasmStringUTF8Length( "<s>" );

// ## Globals
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(global (export <Name name>) <GlobalFields fields>)` )
  = <desc3, (ModuleField)`(export <Name name> (global <GlobalIdx id>))` + desFields>
  when <desc2,id> := getFreshId( desc ),
       <desc3,desFields> := desugar( desc2, (ModuleField)`(global <Id id> <GlobalFields fields>)` );
  
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(global <Id id> (export <Name name>) <GlobalFields fields>)` )
  = <desc2, (ModuleField)`(export <Name name> (global <GlobalIdx id>))` + desFields>
  when <desc2, desFields> := desugar( desc, (ModuleField)`(global <Id id> <GlobalFields fields>)` );

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(global <Id? id> (import <Name modName> <Name globalName>) <GlobalType globalType>)` )
  = <desc, [ (ModuleField)`(import <Name modName> <Name globalName> (global <Id? id> <GlobalType globalType>))` ]>;
  
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(global <Id? id> <GlobalType globalType> <Expr expr>)` )
  = <desc, [ (ModuleField)`(global <Id? id> <GlobalType globalType> <Expr desExpr>)` ]>
  when desExpr := desugar( expr );

private Expr desugar( (Expr)`<Instr* instrs>` ) = concat( (Expr)``, [ x | i <- instrs, x <- desugar( i ) ] );
private Expr concat( e:(Expr)`<Instr* instrs>`, [] ) = e;
private Expr concat( (Expr)`<Instr* instrs>`, [ newInstr, *newInstrs ] ) = concat( (Expr)`<Instr* instrs> <Instr newInstr>`, newInstrs ); 
  
// ## Elements
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(elem <ElemFields f>)` )
  = desugar( desc, (ModuleField)`(elem 0 <ElemFields f>)` );
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(elem <TableIdx idx> <Instr i> <FuncIdx* idxs>)` )
  = desugar( desc, (ModuleField)`(elem <TableIdx idx> (offset <Instr i>) <FuncIdx* idxs>)` );
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(elem <TableIdx idx> (offset <Expr expr>) <FuncIdx* idxs>)` )
  = <desc, [ (ModuleField)`(elem <TableIdx idx> (offset <Expr desExpr>) <FuncIdx* idxs>)` ] >
  when desExpr := desugar( expr );

// ## Data
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(data <DataFields f>)` )
  = desugar( desc, (ModuleField)`(data 0 <DataFields f>)` );

private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(data <MemIdx idx> <Instr i> <DataString b>)` )
  = <desc, [ addInstrs( (ModuleField)`(data <MemIdx idx> (offset) <DataString b>)`, desugar( i ) )]>;
private tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, (ModuleField)`(data <Instr i> <DataString b>)` )
  = <desc, [ addInstrs( (ModuleField)`(data (offset) <DataString b>)`, desugar( i ) ) ]>;

private ModuleField addInstrs( f:(ModuleField)`(data (offset <Instr* instrs>) <DataString b>)`, [] ) = f;
private ModuleField addInstrs( (ModuleField)`(data (offset <Instr* instrs>) <DataString b>)`, list[Instr] newInstrs )
  = addInstrs( (ModuleField)`(data (offset <Instr* instrs> <Instr h>) <DataString b>)`, tail( newInstrs ) )
  when h := head( newInstrs );

private ModuleField addInstrs( f:(ModuleField)`(data <MemIdx idx> (offset <Instr* instrs>) <DataString b>)`, [] ) = f;
private ModuleField addInstrs( (ModuleField)`(data <MemIdx idx> (offset <Instr* instrs>) <DataString b>)`, list[Instr] newInstrs )
  = addInstrs( (ModuleField)`(data <MemIdx idx> (offset <Instr* instrs> <Instr h>) <DataString b>)`, tail( newInstrs ) )
  when h := head( newInstrs );

// Module default
private default tuple[ModuleDesc,list[ModuleField]] desugar( ModuleDesc desc, ModuleField f ) = <desc,[f]>;

// Helpers

private list[Param] desugar( p:(Param)`(param <Id id> <ValType _>)` ) = [ p ];
private list[Param] desugar( p:(Param)`(param <ValType valType> <ValType* valTypes>)` ) = (Param)`(param <ValType valType>)` + desugar( (Param)`(param <ValType* valTypes>)` );
private list[Param] desugar( p:(Param)`(param)` ) = [];
private list[Param] desugar( Param* params ) = [ x | p <- params, x <- desugar( p ) ];

private list[Result] desugar( r:(Result)`(result <Id id> <ValType _>)` ) = [ p ];
private list[Result] desugar( r:(Result)`(result <ValType valType> <ValType* valTypes>)` ) = (Result)`(result <ValType valType>)` + desugar( (Result)`(result <ValType* valTypes>)` );
private list[Result] desugar( r:(Result)`(result)` ) = [];
private list[Result] desugar( Result* results ) = [ x | r <- results, x <- desugar( r ) ];

private Module prependFields( m:(Module)`(module <Id? id> <ModuleField* fields>)`, [] ) = m;
private Module prependFields( m:(Module)`(module <Id? id> <ModuleField* fields>)`, list[ModuleField] newFields )
  = prependFields( (Module)`(module <Id? id> <ModuleField newField> <ModuleField* fields>)`, prefix( newFields ) )
  when newField := last( newFields );

/*FuncBody addLocals( b:(FuncBody)`<Local* locals> <Instr* instrs>`, [] ) = b;
FuncBody addLocals( (FuncBody)`<Local* locals> <Instr* instrs>`, list[Local] newLocals )
  = addLocals( (FuncBody)`<Local* locals> <Local first> <Instr* instrs>`, tail( newLocals ) )
  when first := head( newLocals );*/

// These are made iteratively, to avoid a StackOverflow that may otherwise occur
private FuncBody addLocals( f:(FuncBody)`<Local* locals> <Instr* instrs>`, list[Local] newLocals ) {
  for ( l <- newLocals ) {
    if ( (FuncBody)`<Local* locals> <Instr* instrs>` := f ) {
      f = (FuncBody)`<Local* locals> <Local l> <Instr* instrs>`;
    } else {
      throw AssertionFailed( "Only syntax mismatched. Cannot happen." );
    }
  }
  return f;
}

/*FuncBody addInstrs( b:(FuncBody)`<Local* locals> <Instr* instrs>`, [] ) = b;
FuncBody addInstrs( (FuncBody)`<Local* locals> <Instr* instrs>`, list[Instr] newInstrs )
  = addInstrs( (FuncBody)`<Local* locals> <Instr* instrs> <Instr first>`, tail( newInstrs ) )
  when first := head( newInstrs );*/

// These are made iteratively, to avoid a StackOverflow that may otherwise occur
private FuncBody addInstrs( f:(FuncBody)`<Local* locals> <Instr* instrs>`, list[Instr] newInstrs ) {
  for ( i <- newInstrs ) {
    if ( (FuncBody)`<Local* locals> <Instr* instrs>` := f ) {
      f = (FuncBody)`<Local* locals> <Instr* instrs> <Instr i>`;
    } else {
      throw AssertionFailed( "Only syntax mismatched. Cannot happen." );
    }
  }
  return f;
}

private TypeUse addParams( t:(TypeUse)`<Param* ps> <Result* rs>`, [] ) = t; 
private TypeUse addParams( (TypeUse)`<Param* ps> <Result* rs>`, list[Param] params )
  = addParams( (TypeUse)`<Param* ps> <Param p> <Result* rs>`, tail( params ) )
  when p := head( params );
  
private TypeUse addResults( t:(TypeUse)`<Param* ps> <Result* rs>`, [] ) = t; 
private TypeUse addResults( (TypeUse)`<Param* ps> <Result* rs>`, list[Result] results )
  = addResults( (TypeUse)`<Param* ps> <Result* rs> <Result r>`, tail( results ) )
  when r := head( results );
  
private FuncType addParams( t:(FuncType)`(func <Param* ps> <Result* rs>)`, [] ) = t; 
private FuncType addParams( (FuncType)`(func <Param* ps> <Result* rs>)`, list[Param] params )
  = addParams( (FuncType)`(func <Param* ps> <Param p> <Result* rs>)`, tail( params ) )
  when p := head( params );
  
private FuncType addResults( t:(FuncType)`(func <Param* ps> <Result* rs>)`, [] ) = t; 
private FuncType addResults( (FuncType)`(func <Param* ps> <Result* rs>)`, list[Result] results )
  = addResults( (FuncType)`(func <Param* ps> <Result* rs> <Result r>)`, tail( results ) )
  when r := head( results );

private tuple[ModuleDesc,TypeUse] desugar( ModuleDesc desc, (TypeUse)`(type <TypeIdx idx>) <Param* ps> <Result* rs>` )
  = <desc, (TypeUse)`(type <TypeIdx idx>) <Param* desPs> <Result* desRs>`>
  when (TypeUse)`<Param* desPs> <Result* desRs>` := addResults( addParams( (TypeUse)``, desugar( ps ) ), desugar( rs ) );

private tuple[ModuleDesc,TypeUse] desugar( ModuleDesc desc, (TypeUse)`<Param* ps> <Result* rs>` )
  = <desc2, (TypeUse)`(type <UN idLex>) <Param* desPs> <Result* desRs>`>
  when (TypeUse)`<Param* desPs> <Result* desRs>` := addResults( addParams( (TypeUse)``, desugar( ps ) ), desugar( rs ) ),
       <desc2, id> := findTypeIndex( desc, desPs, desRs ),
       idLex := parse( #UN, "<id>" );

// ## Utils
private set[str] occurringIds( Module m ) {
  set[str] ids = { };
  visit ( m ) {
  case Id i: {
    ids += "<i>";
  }
  }
  return ids;
}

// Obtains non-inlined function types (syntax "Type") from the module
private list[TypeDesc] getFuncTypes( Module m ) {
  list[TypeDesc] types = [];
  visit ( m ) {
  case (Type)`(type <Id? id> (func <Param* ps> <Result* rs>))`: {
    types += typeDesc( getTypes( desugar( ps ) ), getTypes( desugar( rs ) ) );
  }
  }
  return types;
}

/**
 * A generator for fresh identifiers, satisfying the form "$t[id]", for any
 * such identifier that does not yet exist in the source text.
 *
 * From "6.3.5 Identifiers. Conventions":
 * The expansion rules of some abbreviations require insertion of a fresh
 * identifier. That may be any syntactically identifier that does not already
 * occur in the given source text.
 */
private tuple[ModuleDesc,Id] getFreshId( moduleDesc( types, ids ) ) {
  // This is not very efficient, as it starts at '$t0' every time,
  // looping until a free one is found. Though, it has no side-effects,
  // which makes it cleaner.
  str id;
  int index = 0;
  do {
    id = "$t<index>";
    index = index + 1;
  } while ( id in ids );
  return <moduleDesc( types, ids + id ), parse(#Id, id)>;
}

/**
 * A 'typeuse' may alse be replaced entirely by inline parameter and result
 * declarations. In that case, a type index is automatically inserted, having
 * the smallest type index whose definition in the current module is the given
 * function type. If no such index exists, then a new type definition is
 * inserted at the end of the module.
 */
private tuple[ModuleDesc,int] findTypeIndex( m:moduleDesc( types, ids ), Param* params, Result* results ) {
  newType = typeDesc( getTypes( [ p | p <- params ] ), getTypes( [ r | r <- results ] ) );
  int index = 0;
  for ( TypeDesc \type <- types ) {
    if ( \type == newType ) {
      return <m,index>;
    }
    index = index + 1;
  }
  return <moduleDesc( types + newType, ids ), index>;
}
