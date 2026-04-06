# Contributing to llmlite

Thank you for your interest in contributing to llmlite! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## How to Contribute

### Reporting Issues

- Search existing issues before creating a new one
- Provide clear and descriptive titles
- Include code samples, error messages, and environment details
- Use issue templates when available

### Suggesting Features

- Open a discussion first to gauge interest
- Describe the use case and expected behavior
- Explain why this feature would benefit the project

### Pull Requests

1. **Fork the repository** and create a branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Follow the coding style**:
   - Zig 0.15+ is required
   - Run `zig build` to ensure compilation
   - Run `zig build test` to ensure tests pass
   - Follow existing code patterns in the project

3. **Write meaningful commit messages**:
   ```
   feat(provider): add thinking mode support for Kimi K2.5
   
   Add thinking parameter support to enable chain-of-thought reasoning
   for the Kimi K2.5 model. Includes tests for enabled/disabled states.
   ```

4. **Submit your pull request**:
   - Reference any related issues
   - Ensure CI passes
   - Be responsive to review feedback

## Development Setup

### Prerequisites

- Zig 0.15 or later
- Git

### Building

```bash
# Clone the repository
git clone https://github.com/zouyee/llmlite.git
cd llmlite

# Build the project
zig build

# Run tests
zig build test
```

### Running Specific Tests

```bash
# Run provider-specific tests
zig build kimi-test
zig build minimax-test
zig build test

# Run all tests
zig build test
```

## Project Structure

```
llmlite/
├── src/
│   ├── provider/          # Provider implementations
│   │   ├── openai.zig
│   │   ├── google.zig
│   │   ├── minimax/
│   │   │   ├── mod.zig
│   │   │   ├── tts.zig
│   │   │   ├── video.zig
│   │   │   ├── image.zig
│   │   │   └── music.zig
│   │   └── kimi/
│   │       └── mod.zig
│   ├── chat.zig           # Chat completion types
│   ├── http.zig           # HTTP client
│   └── ...
├── docs/
│   └── providers/         # Provider documentation
│       ├── openai.md
│       ├── google-gemini.md
│       ├── minimax.md
│       └── kimi.md
├── examples/             # Example code
└── tests/               # Test files
```

## Coding Guidelines

### Zig Conventions

1. **Error handling**: Use Zig's built-in error types and try/catch
2. **Memory**: Prefer allocation-free patterns when possible
3. **Types**: Use structured types, avoid `any`
4. **Documentation**: Document public APIs with doc comments

### Example

```zig
/// A brief description of what this function does.
///
/// Longer description if needed, explaining the behavior,
/// parameters, and return value.
///
/// # Parameters
/// - `allocator`: Memory allocator for internal use
/// - `params`: The parameters for the operation
///
/// # Errors
/// Returns an error if the operation fails
pub fn myFunction(allocator: std.mem.Allocator, params: MyParams) !Result {
    // implementation
}
```

## Adding a New Provider

To add a new LLM provider:

1. Create provider module in `src/provider/<name>/`
2. Add provider configuration to `src/provider/registry.zig`
3. Create request transformer if API format differs from OpenAI
4. Add tests in `src/test/<name>_test.zig`
5. Add documentation in `docs/providers/<name>.md`

## Documentation

- Update README.md if adding new features
- Add provider documentation in `docs/providers/`
- Include code examples for new functionality

## License

By contributing to llmlite, you agree that your contributions will be licensed under the GNU Affero General Public License version 3 (AGPL-3.0).
