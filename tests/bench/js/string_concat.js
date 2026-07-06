function concat(n) {
    let s = "";
    for (let i = 0; i < n; i++)
        s += "x";
    return s.length;
}
console.log(concat(10000));
