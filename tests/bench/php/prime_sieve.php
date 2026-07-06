<?php
function sieve($n) {
    $count = 0;
    for ($i = 2; $i < $n; $i++) {
        $is_prime = true;
        for ($j = 2; $j * $j <= $i; $j++) {
            if ($i % $j == 0) { $is_prime = false; break; }
        }
        if ($is_prime) $count++;
    }
    return $count;
}
echo sieve(5000) . "\n";
