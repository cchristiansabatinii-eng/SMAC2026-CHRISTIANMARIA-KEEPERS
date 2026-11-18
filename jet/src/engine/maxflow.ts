/** Dinic's max-flow. Small, exact, and fast enough to re-run every second. */
export class MaxFlow {
  private head: number[];
  private to: number[] = [];
  private cap: number[] = [];
  private next: number[] = [];
  private level: number[] = [];
  private it: number[] = [];

  constructor(private n: number) {
    this.head = new Array(n).fill(-1);
  }

  addEdge(u: number, v: number, c: number): number {
    const id = this.to.length;
    this.to.push(v, u);
    this.cap.push(c, 0);
    this.next.push(this.head[u], this.head[v]);
    this.head[u] = id;
    this.head[v] = id + 1;
    return id;
  }

  /** Flow currently carried by an edge returned from addEdge. */
  flowOn(edge: number): number {
    return this.cap[edge + 1];
  }

  private bfs(s: number, t: number): boolean {
    this.level = new Array(this.n).fill(-1);
    const q = [s];
    this.level[s] = 0;
    for (let i = 0; i < q.length; i++) {
      const u = q[i];
      for (let e = this.head[u]; e !== -1; e = this.next[e]) {
        if (this.cap[e] > 0 && this.level[this.to[e]] < 0) {
          this.level[this.to[e]] = this.level[u] + 1;
          q.push(this.to[e]);
        }
      }
    }
    return this.level[t] >= 0;
  }

  private dfs(u: number, t: number, f: number): number {
    if (u === t) return f;
    for (; this.it[u] !== -1; this.it[u] = this.next[this.it[u]]) {
      const e = this.it[u];
      const v = this.to[e];
      if (this.cap[e] > 0 && this.level[v] === this.level[u] + 1) {
        const d = this.dfs(v, t, Math.min(f, this.cap[e]));
        if (d > 0) {
          this.cap[e] -= d;
          this.cap[e ^ 1] += d;
          return d;
        }
      }
    }
    return 0;
  }

  run(s: number, t: number): number {
    let flow = 0;
    while (this.bfs(s, t)) {
      this.it = this.head.slice();
      let f: number;
      while ((f = this.dfs(s, t, Infinity)) > 0) flow += f;
    }
    return flow;
  }
}
