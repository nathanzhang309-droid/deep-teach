// WebKit 18 has getReader(), but does not expose ReadableStream async iteration.
// PDF.js 6 uses for-await in getTextContent, including in its legacy build.
// Upstream: https://github.com/mozilla/pdf.js/issues/21924
export function installStreamIterator(prototype: any = ReadableStream.prototype) {
  if (prototype[Symbol.asyncIterator]) return;
  Object.defineProperty(prototype, Symbol.asyncIterator, {
    configurable: true, writable: true,
    value: async function* (this: ReadableStream, options: {preventCancel?: boolean} = {}) {
      const reader = this.getReader(); let complete = false;
      try {
        while (true) {
          const {value, done} = await reader.read();
          if (done) {complete = true; return;}
          yield value;
        }
      } finally {
        try {if (!complete && !options.preventCancel) await reader.cancel();}
        finally {reader.releaseLock();}
      }
    },
  });
}
installStreamIterator();
