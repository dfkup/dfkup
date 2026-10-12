let a = [];
for (let i = 0; i < 200000; i++) a.push(i);
let total = 0;
for (let j = 0; j < a.length; j++) total += a[j];
console.log(total);
