// Browser backend for the play page: runs the engine from wyrd.wasm instead of
// asking the local play.py server. Defines window.WYRD_BACKEND before the page script runs.
(function () {
  let exp = null;
  const netCache = {};

  async function init() {
    if (exp) return exp;
    const bytes = await (await fetch('wyrd.wasm')).arrayBuffer();   // arrayBuffer: works whatever MIME type the host sends
    exp = (await WebAssembly.instantiate(bytes, {})).instance.exports;
    return exp;
  }

  async function netBytes(name) {
    if (name === 'material') return new Uint8Array(0);
    if (!netCache[name]) {
      const r = await fetch('nets/' + name + '.bin');
      if (!r.ok) throw new Error('cannot load net ' + name);
      netCache[name] = new Uint8Array(await r.arrayBuffer());
    }
    return netCache[name];
  }

  function put(x, bytes) {              // copy bytes into the module's memory
    const p = x.alloc(bytes.length);
    new Uint8Array(x.memory.buffer, p, bytes.length).set(bytes);
    return p;
  }

  window.WYRD_BACKEND = {
    nets: async () => (await fetch('nets.json')).json(),
    move: async (fen, nodes, net) => {
      const x = await init();
      const f = new TextEncoder().encode(fen), nb = await netBytes(net);
      const fp = put(x, f), np = put(x, nb);
      try {
        const n = x.best_move(fp, f.length, nodes, np, nb.length);
        const text = new TextDecoder().decode(new Uint8Array(x.memory.buffer, x.result_ptr(), n));
        if (text[0] === '!') return { error: text.slice(1) };
        const [move, score] = text.split(' ');
        return { move, score: parseInt(score, 10) };
      } finally { x.dealloc(fp, f.length); x.dealloc(np, nb.length); }
    },
  };
})();
