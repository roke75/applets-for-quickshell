#!/usr/bin/env python3
"""Safe arithmetic: only numbers, operators and math functions are evaluated."""
import ast
import json
import math
import operator
import os
import re
import sys
from pathlib import Path

HISTORY = Path(os.environ.get("APPLET_DATA", ".")) / "history.json"
OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
       ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod,
       ast.Pow: operator.pow, ast.USub: operator.neg, ast.UAdd: operator.pos}
NAMES = {k: v for k, v in vars(math).items() if not k.startswith("_")}


def evaluate(node):
    """Evaluate a parsed expression: numbers, arithmetic and math functions only."""
    if isinstance(node, ast.Expression):
        return evaluate(node.body)
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in OPS:
        left, right = evaluate(node.left), evaluate(node.right)
        if isinstance(node.op, ast.Pow) and abs(right) > 1000:  # would take ages
            raise ValueError("exponent too large")
        return OPS[type(node.op)](left, right)
    if isinstance(node, ast.UnaryOp) and type(node.op) in OPS:
        return OPS[type(node.op)](evaluate(node.operand))
    if isinstance(node, ast.Name) and isinstance(NAMES.get(node.id), (int, float)):
        return NAMES[node.id]
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and callable(NAMES.get(node.func.id)):
        return NAMES[node.func.id](*[evaluate(a) for a in node.args])
    raise ValueError("unsupported expression")


def calculate(text):
    # Calculator notation: ^ for powers, × and ÷, decimal commas, "15% of 80".
    expr = text.strip().replace("^", "**").replace("×", "*").replace("÷", "/").replace(",", ".")
    expr = re.sub(r"([\d.]+)\s*%\s*of\s*", r"\1/100*", expr)
    value = evaluate(ast.parse(expr, mode="eval"))
    if isinstance(value, float) and value.is_integer() and abs(value) < 1e15:
        value = int(value)
    return f"{value:.10g}" if isinstance(value, float) else str(value)


history = json.loads(HISTORY.read_text()) if HISTORY.exists() else []
state = {}
if sys.argv[1:2] == ["input"]:
    try:
        result = calculate(sys.argv[2])
        history = [[sys.argv[2].strip(), result]] + history[:19]  # newest first, 20 kept
        HISTORY.write_text(json.dumps(history))
        state["text"] = result
    except Exception as error:  # report any evaluation failure to the user
        state["error"] = f"Cannot evaluate: {error}"
elif sys.argv[1:3] == ["action", "clear"]:
    history = []
    HISTORY.write_text("[]")

# Rows copy their result and keep the popup open for further calculations.
state["items"] = [{"text": f"= {r}", "detail": e, "copy": r, "close": False} for e, r in history]
if history:
    state["items"].append({"text": "Clear history", "class": "muted", "run": "clear"})
print(json.dumps(state))
