#!/usr/bin/env python3
"""
Convert JSON to Lua table.

Usage:
    python json_to_lua.py input.json [output.lua]
    cat input.json | python json_to_lua.py > output.lua
"""

import sys
import json
import re
from typing import Any, TextIO

# Lua 标识符规则：以字母或下划线开头，后跟字母、数字、下划线
_LUA_IDENTIFIER = re.compile(r'^[a-zA-Z_][a-zA-Z0-9_]*$')


def _escape_lua_string(s: str) -> str:
    """转义字符串中的特殊字符，使其可以放入 Lua 双引号字符串。"""
    # 需要转义：反斜杠、双引号、换行、回车、制表符等
    s = s.replace('\\', '\\\\')
    s = s.replace('"', '\\"')
    s = s.replace('\n', '\\n')
    s = s.replace('\r', '\\r')
    s = s.replace('\t', '\\t')
    # 可以按需添加更多控制字符转义
    return f'"{s}"'


def _indent(level: int, size: int = 4) -> str:
    return ' ' * (level * size)


def _write_lua_value(obj: Any, out: TextIO, level: int = 0, indent_size: int = 4):
    """递归将 Python 对象写入 Lua 表示。"""
    if obj is None:
        out.write('nil')
    elif isinstance(obj, bool):
        out.write('true' if obj else 'false')
    elif isinstance(obj, (int, float)):
        out.write(str(obj))
    elif isinstance(obj, str):
        out.write(_escape_lua_string(obj))
    elif isinstance(obj, list):
        # Lua 数组部分
        out.write('{\n')
        for i, item in enumerate(obj):
            out.write(_indent(level + 1, indent_size))
            _write_lua_value(item, out, level + 1, indent_size)
            if i < len(obj) - 1:
                out.write(',')
            out.write('\n')
        out.write(_indent(level, indent_size) + '}')
    elif isinstance(obj, dict):
        # Lua 表（键值对）
        out.write('{\n')
        items = list(obj.items())
        for i, (k, v) in enumerate(items):
            out.write(_indent(level + 1, indent_size))
            # 键的处理
            if isinstance(k, str) and _LUA_IDENTIFIER.match(k):
                # 合法标识符：直接写标识符形式
                out.write(f'{k} = ')
            else:
                # 其他情况用方括号形式 [key] = value
                out.write('[')
                _write_lua_value(k, out, level + 1, indent_size)
                out.write('] = ')
            # 值
            _write_lua_value(v, out, level + 1, indent_size)
            if i < len(items) - 1:
                out.write(',')
            out.write('\n')
        out.write(_indent(level, indent_size) + '}')
    else:
        raise TypeError(f'Unsupported type: {type(obj)}')


def json_to_lua(json_data: str) -> str:
    """将 JSON 字符串转换为 Lua 表字符串。"""
    obj = json.loads(json_data)
    from io import StringIO
    out = StringIO()
    _write_lua_value(obj, out)
    return out.getvalue()


def main():
    # 参数解析
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        sys.exit(0)

    input_file = None
    output_file = None

    # 如果提供了输入文件名
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    if len(sys.argv) > 2:
        output_file = sys.argv[2]

    # 读取 JSON 数据
    if input_file:
        with open(input_file, 'r', encoding='utf-8') as f:
            json_str = f.read()
    else:
        json_str = sys.stdin.read()

    # 转换为 Lua
    try:
        lua_code = json_to_lua(json_str)
    except Exception as e:
        sys.stderr.write(f'Error: {e}\n')
        sys.exit(1)

    # 输出
    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(lua_code)
    else:
        sys.stdout.write(lua_code)


if __name__ == '__main__':
    main()