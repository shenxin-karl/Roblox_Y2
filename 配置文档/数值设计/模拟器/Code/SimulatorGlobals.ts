declare global {
  function print(...values: unknown[]): void;
  function error(...values: unknown[]): void;
}

export {};
