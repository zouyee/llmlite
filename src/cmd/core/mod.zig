//! Core Infrastructure for llmlite-cmd
//!
//! This module provides the core building blocks:
//! - runner: 6-phase execution framework
//! - filter: 14 filtering strategies
//! - tracking: SQLite-based token tracking
//! - tee: failure recovery
//! - utils: utility functions
//! - gain: token savings analytics
//! - hook: AI tool integration hooks
//! - discover: find missed savings opportunities
//! - session: Claude Code session tracking
//! - config: TOML configuration file support
//! - audit: hook usage auditing
//! - integrity: SHA-256 hook verification
//! - learn: CLI error pattern detection
//! - cc_economics: Claude API spending analysis
//! - trust: project-local TOML filter trust management
//! - ruff: Python lint JSON filtering
//! - npm: npm output filtering
//! - pnpm: pnpm output filtering
//! - tsc: TypeScript compiler JSON filtering
//! - golangci_lint: Go lint JSON filtering
//! - vitest: JavaScript test runner filtering
//! - gh: GitHub CLI filtering
//! - docker: Docker container filtering
//! - kubectl: Kubernetes CLI filtering
//! - prettier: Code formatter filtering
//! - mypy: Python type checker filtering
//! - pip: Python package manager filtering
//! - rspec: Ruby test runner filtering
//! - rake: Ruby task runner filtering
//! - rubocop: Ruby linter filtering
//! - dotnet: .NET CLI filtering
//! - playwright: E2E test runner filtering
//! - prisma: Database ORM filtering
//! - nextjs: Next.js framework filtering
//! - eslint: JavaScript linter filtering
//! - aws: AWS CLI filtering
//! - curl: HTTP client filtering

// Re-export all submodules using relative imports
// These work because build.zig creates each as a separate module
pub const runner = @import("runner");
pub const filter = @import("filter");
pub const tracking = @import("tracking");
pub const tee = @import("tee");
pub const utils = @import("utils");
pub const gain = @import("gain");
pub const hook = @import("hook");
pub const discover = @import("discover");
pub const session = @import("session");
pub const config = @import("config");
pub const audit = @import("audit");
pub const integrity = @import("integrity");
pub const learn = @import("learn");
pub const cc_economics = @import("cc_economics");
pub const trust = @import("trust");
pub const rules = @import("rules");
pub const lexer = @import("lexer");
pub const pytest = @import("pytest");
pub const cargo = @import("cargo");
pub const go_test = @import("go_test");
pub const java = @import("java");
pub const json = @import("json");
pub const ruff = @import("ruff");
pub const npm = @import("npm");
pub const pnpm = @import("pnpm");
pub const tsc = @import("tsc");
pub const golangci_lint = @import("golangci_lint");
pub const vitest = @import("vitest");
pub const docker = @import("docker");
pub const kubectl = @import("kubectl");
pub const prettier = @import("prettier");
pub const mypy = @import("mypy");
pub const pip = @import("pip");
pub const rspec = @import("rspec");
pub const rake = @import("rake");
pub const rubocop = @import("rubocop");
pub const dotnet = @import("dotnet");
pub const playwright = @import("playwright");
pub const prisma = @import("prisma");
pub const nextjs = @import("nextjs");
pub const eslint = @import("eslint");
pub const aws = @import("aws");
pub const curl = @import("curl");
pub const proxy_helpers = @import("proxy_helpers");
