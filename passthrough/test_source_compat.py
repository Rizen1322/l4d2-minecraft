"""Guard the conditional grammar rejected by retail L4D2's Squirrel compiler.

This is a targeted source lint, not a replacement for retail VM verification.
Standalone SQ3 accepts chained ternaries which the installed Source VM rejects.
"""
import re
from pathlib import Path
import unittest

_TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[?():;,{}\[\]]', re.DOTALL)


def ambiguous_conditionals(source):
    """Return line/column of nested ?: without an explicit branch delimiter."""
    depth = []
    conditional = {}
    violations = []
    for match in _TOKEN.finditer(source):
        token = match.group()
        if token.startswith(('//', '/*', '"', "'")):
            continue
        level = tuple(depth)
        if token == '?':
            if level in conditional:
                start = match.start()
                violations.append((source.count('\n', 0, start) + 1, start - source.rfind('\n', 0, start)))
            conditional[level] = True
        elif token in ('(', '[', '{'):
            depth.append(token)
        elif token in (')', ']', '}'):
            conditional.pop(level, None)
            if depth:
                depth.pop()
        elif token in (';', ','):
            conditional.pop(level, None)
    return violations


class RetailConditionalCompatibilityTests(unittest.TestCase):
    def test_retail_rejected_difficulty_and_event_routing_patterns(self):
        self.assertEqual(len(ambiguous_conditionals('local n=d=="Impossible"?2:d=="Hard"?1:0;')), 1)
        self.assertEqual(len(ambiguous_conditionals('local n="victim" in e?e.victim:"userid" in e?e.userid:"attacker" in e?e.attacker:0;')), 2)

    def test_explicit_branch_parentheses_and_separate_arguments_are_unambiguous(self):
        self.assertEqual(ambiguous_conditionals('local n=a?b:(c?d:e); f(a?b:c,d?e:f);'), [])
        self.assertEqual(ambiguous_conditionals('local n=a?(b?c:d):e;'), [])

    def test_literals_comments_and_array_commas_do_not_hide_nested_branch(self):
        self.assertEqual(ambiguous_conditionals('local x="a?b:c?d:e"; // a?b:c?d:e\n/* a?b:c?d:e */'), [])
        self.assertEqual(len(ambiguous_conditionals('local n=a?[1,2]:b?3:4;')), 1)

    def test_new_source_modules_avoid_retail_rejected_conditional_grammar(self):
        root = Path(__file__).parent / 'host'
        for name in ('l4d2mc_coop.nut', 'l4d2mc_flight.nut'):
            with self.subTest(module=name):
                self.assertEqual(ambiguous_conditionals((root/name).read_text(encoding='utf-8')), [], name)


if __name__ == '__main__':
    unittest.main()
