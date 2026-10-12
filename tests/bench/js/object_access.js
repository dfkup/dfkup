function churn(n) {
    const p = { x: 0, y: 0 };
    let cycles = 0;
    for (let i = 0; i < n; i++) {
        p.x = p.x + 1;
        p.y = p.y + p.x;
        if (p.x === 1000) {
            p.x = 0;
            p.y = 0;
            cycles++;
        }
    }
    return cycles;
}
console.log(churn(1000000));
