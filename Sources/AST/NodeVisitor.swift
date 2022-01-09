/// A type that visits declaration nodes.
public protocol DeclVisitor {

  associatedtype DeclResult

  mutating func visit(_ decl: inout StructDecl) -> DeclResult
  mutating func visit(_ decl: inout BindingDecl) -> DeclResult
  mutating func visit(_ decl: inout ParamDecl) -> DeclResult

}

/// A type that visits expression nodes.
public protocol ExprVisitor {

  associatedtype ExprResult

  mutating func visit(_ expr: inout IntExpr) -> ExprResult
  mutating func visit(_ expr: inout FloatExpr) -> ExprResult
  mutating func visit(_ expr: inout ArrayExpr) -> ExprResult
  mutating func visit(_ expr: inout StructExpr) -> ExprResult
  mutating func visit(_ expr: inout FuncExpr) -> ExprResult
  mutating func visit(_ expr: inout CallExpr) -> ExprResult
  mutating func visit(_ expr: inout InfixExpr) -> ExprResult
  mutating func visit(_ expr: inout OperExpr) -> ExprResult
  mutating func visit(_ expr: inout InoutExpr) -> ExprResult
  mutating func visit(_ expr: inout BindingExpr) -> ExprResult
  mutating func visit(_ expr: inout FuncBindingExpr) -> ExprResult
  mutating func visit(_ expr: inout AssignExpr) -> ExprResult
  mutating func visit(_ expr: inout CondExpr) -> ExprResult
  mutating func visit(_ expr: inout WhileExpr) -> ExprResult
  mutating func visit(_ expr: inout CastExpr) -> ExprResult
  mutating func visit(_ expr: inout ErrorExpr) -> ExprResult

  mutating func visit(_ expr: inout NamePath) -> ExprResult
  mutating func visit(_ expr: inout PropPath) -> ExprResult
  mutating func visit(_ expr: inout ElemPath) -> ExprResult

}

/// A type that visits path nodes.
public protocol PathVisitor {

  associatedtype PathResult

  mutating func visit(path: inout NamePath) -> PathResult
  mutating func visit(path: inout ElemPath) -> PathResult
  mutating func visit(path: inout PropPath) -> PathResult

}

/// A type that visits signature nodes.
public protocol SignVisitor {

  associatedtype SignResult

  mutating func visit(_ sign: inout TypeDeclRefSign) -> SignResult
  mutating func visit(_ sign: inout ArraySign) -> SignResult
  mutating func visit(_ sign: inout FuncSign) -> SignResult
  mutating func visit(_ sign: inout InoutSign) -> SignResult
  mutating func visit(_ sign: inout ErrorSign) -> SignResult

}
