# Pathological SQL Obfuscation Test Cases

## Why are these pathological?
Because obfuscating dialect-specific SQL is difficult without building a comprehensive lexer, so there are some edge cases where agents are expected to err on the side of over-obfuscation, even though the resulting obfuscation differs from how a perfect lexer might parse and obfuscate it.