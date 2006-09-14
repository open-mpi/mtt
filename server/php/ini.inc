<?php

# Reference:
#   http://us3.php.net/manual/en/function.parse-ini-file.php

function write_ini_file($path, $assoc_array) {

   $content = '';
   $sections = '';

   foreach ($assoc_array as $key => $item) {
       if (is_array($item)) {
           $sections .= "\n[{$key}]\n";
           foreach ($item as $key2 => $item2) {
               if (is_numeric($item2) || is_bool($item2))
                   $sections .= "{$key2} = {$item2}\n";
               else
                   $sections .= "{$key2} = \"{$item2}\"\n";
           }
       }
       else {
           if(is_numeric($item) || is_bool($item))
               $content .= "{$key} = {$item}\n";
           else
               $content .= "{$key} = \"{$item}\"\n";
       }
   }

   $content .= $sections;

   if (!$handle = fopen($path, 'w'))
       return false;

   if (!fwrite($handle, $content))
       return false;

   fclose($handle);
   return true;
}

?>
