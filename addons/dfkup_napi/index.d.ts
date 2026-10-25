/**
 * Type definitions for dfkup — Node.js native bindings for the dfkup
 * scripting language (built with denim). The standard library is
 * statically linked, so `import "std/..."` works with no extra files.
 */

/** Run a dfkup script from source and return its result. */
export function run(code: string): string;

/** Run a dfkup script from a file. */
export function runFile(path: string): string;

/** Run a config.kup file. */
export function runConfig(path: string): string;

/** Run one configured command from a config.kup file. */
export function runConfigCommand(path: string, command: string): string;

/** Parse a dfkup script and return its AST as JSON. */
export function ast(code: string): string;

/** Package version. */
export const version: string;

/** Filesystem path of the loaded `.node` binary. */
export const binaryPath: string;

/** The `<platform>-<arch>` pair that was loaded. */
export const nativePair: string;