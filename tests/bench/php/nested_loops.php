<?php
function nested($n) {
    $total = 0;
    for ($i = 0; $i < $n; $i++)
        for ($j = 0; $j < $n; $j++)
            for ($k = 0; $k < $n; $k++)
                $total++;
    return $total;
}
echo nested(60) . "\n";
