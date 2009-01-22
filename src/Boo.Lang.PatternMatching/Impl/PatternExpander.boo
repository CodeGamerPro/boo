namespace Boo.Lang.PatternMatching.Impl

import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast

# import the pre compiled version of the match macro
import Boo.Lang.PatternMatching from Boo.Lang.PatternMatching

class PatternExpander:
	
	def expand(matchValue as Expression, pattern as Expression) as Expression:
		match pattern:
			case MethodInvocationExpression():
				return expandObjectPattern(matchValue, pattern)
				
			case MemberReferenceExpression():
				return expandValuePattern(matchValue, pattern)
				
			case ReferenceExpression():
				return expandBindPattern(matchValue, pattern)
				
			case QuasiquoteExpression():
				return expandQuasiquotePattern(matchValue, pattern)
				
			case [| $l = $r |]:
				return expandCapturePattern(matchValue, pattern)
				
			case [| $l | $r |]:
				return expandEitherPattern(matchValue, pattern)
				
			case ArrayLiteralExpression():
				return expandFixedSizePattern(matchValue, pattern)
				
			otherwise:
				return expandValuePattern(matchValue, pattern)
		
	def expandEitherPattern(matchValue as Expression, node as BinaryExpression) as Expression:
		l = expand(matchValue, node.Left)
		r = expand(matchValue, node.Right)
		return [| $l or $r |]
		
	def expandBindPattern(matchValue as Expression, node as ReferenceExpression):
		return [| __eval__($node = $matchValue, true) |]
		
	def expandValuePattern(matchValue as Expression, node as Expression):
		return [| $matchValue == $node |]
		
	def expandCapturePattern(matchValue as Expression, node as BinaryExpression):
		return expandObjectPattern(matchValue, node.Left, node.Right)
		
	def expandObjectPattern(matchValue as Expression, node as MethodInvocationExpression) as Expression:
	
		if len(node.NamedArguments) == 0 and len(node.Arguments) == 0:
			return [| $matchValue isa $(typeRef(node)) |]
			 
		return expandObjectPattern(matchValue, newTemp(node), node)
		
	def expandObjectPattern(matchValue as Expression, temp as ReferenceExpression, node as MethodInvocationExpression) as Expression:
		
		condition = [| ($matchValue isa $(typeRef(node))) and __eval__($temp = cast($(typeRef(node)), $matchValue), true) |]
		condition.LexicalInfo = node.LexicalInfo
		
		for member in node.Arguments:
			assert member isa ReferenceExpression, "Invalid argument '${member}' in pattern '${node}'."
			memberRef = MemberReferenceExpression(member.LexicalInfo, temp.CloneNode(), member.ToString())
			condition = [| $condition and __eval__($member = $memberRef, true) |]  
			
		for member in node.NamedArguments:
			namedArgCondition = expandMemberPattern(temp.CloneNode(), member)
			condition = [| $condition and $namedArgCondition |]
			
		return condition
	
	class QuasiquotePatternBuilder(DepthFirstVisitor):
		
		static final Ast = [| Boo.Lang.Compiler.Ast |]
		
		_parent as PatternExpander
		_pattern as Expression
		
		def constructor(parent as PatternExpander):
			_parent = parent
		
		def build(node as QuasiquoteExpression):
			return expand(node.Node)
			
		def expand(node as Node):
			node.Accept(self)
			expansion = _pattern
			_pattern = null
			assert expansion is not null, "Unsupported pattern '${node}'"
			return expansion
			
		def push(srcNode as Node, e as Expression):
			assert _pattern is null
			e.LexicalInfo = srcNode.LexicalInfo
			_pattern = e
			
		override def OnSpliceExpression(node as SpliceExpression):
			_pattern = node.Expression
			
		override def OnSpliceTypeReference(node as SpliceTypeReference):
			_pattern = node.Expression
			
		def expandFixedSize(items):
			a = [| (,) |]
			for item in items:
				a.Items.Add(expand(item))
			return a
			
		override def OnOmittedExpression(node as OmittedExpression):
			_pattern = [| $Ast.OmittedExpression.Instance |]
			
		override def OnSlice(node as Slice):
			ctor = [| $Ast.Slice() |]
			expandProperty ctor, "Begin", node.Begin
			expandProperty ctor, "End", node.End
			expandProperty ctor, "Step", node.Step
			push node, ctor
			
		def expandProperty(ctor as MethodInvocationExpression, name as string, value as Expression):
			if value is null: return
			ctor.NamedArguments.Add(ExpressionPair(First: ReferenceExpression(name), Second: expand(value)))
			
		override def OnMacroStatement(node as MacroStatement):
			if len(node.Arguments) > 0:
				push node, [| $Ast.MacroStatement(Name: $(node.Name), Arguments: $(expandFixedSize(node.Arguments))) |]
			else:
				push node, [| $Ast.MacroStatement(Name: $(node.Name)) |]
			
		override def OnSlicingExpression(node as SlicingExpression):
			push node, [| $Ast.SlicingExpression(Target: $(expand(node.Target)), Indices: $(expandFixedSize(node.Indices))) |]
			
		override def OnTryCastExpression(node as TryCastExpression):
			push node, [| $Ast.TryCastExpression(Target: $(expand(node.Target)), Type: $(expand(node.Type))) |]
			
		override def OnMethodInvocationExpression(node as MethodInvocationExpression):
			if len(node.Arguments) > 0:
				pattern = [| $Ast.MethodInvocationExpression(Target: $(expand(node.Target)), Arguments: $(expandFixedSize(node.Arguments))) |]
			else:
				pattern = [| $Ast.MethodInvocationExpression(Target: $(expand(node.Target))) |]
			push node, pattern
			
		override def OnBoolLiteralExpression(node as BoolLiteralExpression):
			push node, [| $Ast.BoolLiteralExpression(Value: $node) |]
			
		override def OnNullLiteralExpression(node as NullLiteralExpression):
			push node, [| $Ast.NullLiteralExpression() |]
			
		override def OnUnaryExpression(node as UnaryExpression):
			push node, [| $Ast.UnaryExpression(Operator: UnaryOperatorType.$(node.Operator.ToString()), Operand: $(expand(node.Operand))) |]
			
		override def OnBinaryExpression(node as BinaryExpression):
			push node, [| $Ast.BinaryExpression(Operator: BinaryOperatorType.$(node.Operator.ToString()), Left: $(expand(node.Left)), Right: $(expand(node.Right))) |]
		
		override def OnReferenceExpression(node as ReferenceExpression):
			push node, [| $Ast.ReferenceExpression(Name: $(node.Name)) |]
			
		override def OnSuperLiteralExpression(node as SuperLiteralExpression):
			push node, [| $Ast.SuperLiteralExpression() |]
			
	def objectPatternFor(node as QuasiquoteExpression):
		return QuasiquotePatternBuilder(self).build(node)
		
	def expandQuasiquotePattern(matchValue as Expression, node as QuasiquoteExpression) as Expression:
		return expandObjectPattern(matchValue, objectPatternFor(node))
		
	def expandMemberPattern(matchValue as Expression, member as ExpressionPair):
		memberRef = MemberReferenceExpression(member.First.LexicalInfo, matchValue, member.First.ToString())	
		return expand(memberRef, member.Second)
		
	def expandFixedSizePattern(matchValue as Expression, pattern as ArrayLiteralExpression):
		condition = [| $(len(pattern.Items)) == len($matchValue) |]
		i = 0
		for item in pattern.Items:
			itemValue = [| $matchValue[$i] |]
			itemPattern = expand(itemValue, item)
			condition = [| $condition and $itemPattern |]
			++i
		return condition
		
	def typeRef(node as MethodInvocationExpression):
		return node.Target
		
def newTemp(e as Expression):
	return ReferenceExpression(
			LexicalInfo: e.LexicalInfo,
			Name: "$match${CompilerContext.Current.AllocIndex()}")