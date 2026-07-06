<?php
function concat($n) {
    $s = "";
    for ($i = 0; $i < $n; $i++)
        $s .= "x";
    return strlen($s);
}
echo concat(10000) . "\n";
