<?php
function accumulate($n) {
    $x = 1.0;
    for ($i = 0; $i < $n; $i++) $x = $x * 1.000001 + 0.5;
    return $x;
}
echo accumulate(2000000) . "\n";
