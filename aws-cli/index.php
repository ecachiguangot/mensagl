<?php
// Datos de conexión (Ajusta con tus datos de RDS)
$host = "cms-database.cvoua4kkog02.us-east-1.rds.amazonaws.com"; 
$user = "admin";
$pass = "Admin123";
$db   = "wordpress_db";

$conn = new mysqli($host, $user, $pass, $db);

if ($conn->connect_error) {
    die("Error de conexión: " . $conn->connect_error);
}

echo "<h1>¡Felicidades EDISON!</h1>";
echo "<p>Conexión exitosa a la base de datos RDS.</p>";
echo "<p>Servidor Web Privado respondiendo a través del Proxy.</p>";
?>
