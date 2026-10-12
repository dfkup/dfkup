<?php
function bump($x) { return $x + 1; }
function hammer($n) {
    $total = 0;
    for ($i = 0; $i < $n; $i++) $total = bump($total);
    return $total;
}
echo hammer(500000) . "\n";
