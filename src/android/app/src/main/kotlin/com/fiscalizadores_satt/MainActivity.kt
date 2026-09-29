package com.fiscalizadores_satt

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.location.Geocoder
import java.util.Locale
import java.util.concurrent.Executors
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val geocodingExecutor = Executors.newSingleThreadExecutor()
    private var pendingResult: MethodChannel.Result? = null
    private var pendingNumber: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sat/ubicaciones").setMethodCallHandler { call, result ->
            if (call.method != "buscarDireccion") { result.notImplemented(); return@setMethodCallHandler }
            val direccion = call.argument<String>("direccion")?.trim() ?: ""
            if (direccion.isEmpty()) { result.success(null); return@setMethodCallHandler }
            if (!Geocoder.isPresent()) {
                result.error("GEOCODER_UNAVAILABLE", "Este teléfono no tiene un servicio de búsqueda de direcciones disponible.", null)
                return@setMethodCallHandler
            }
            geocodingExecutor.execute {
                try {
                    @Suppress("DEPRECATION")
                    val direcciones = Geocoder(applicationContext, Locale("es", "PE")).getFromLocationName(direccion, 1)
                    val encontrada = direcciones?.firstOrNull()
                    // No presentar el centro de una ciudad como si fuera un domicilio.
                    val punto = if (encontrada != null && !encontrada.thoroughfare.isNullOrBlank())
                        mapOf("lat" to encontrada.latitude, "lng" to encontrada.longitude) else null
                    runOnUiThread { result.success(punto) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("GEOCODER_ERROR", "No se pudo localizar la dirección. Revise su conexión e intente de nuevo.", null) }
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sat/contacto").setMethodCallHandler { call, result ->
            if (call.method != "llamar") { result.notImplemented(); return@setMethodCallHandler }
            val numero = call.argument<String>("numero") ?: ""
            if (!Regex("^\\+?[0-9]{6,15}$").matches(numero)) {
                result.error("INVALID_NUMBER", "El número no es válido.", null)
            } else if (pendingResult != null) {
                result.error("BUSY", "Ya hay una solicitud de llamada pendiente.", null)
            } else if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
                llamar(numero, result)
            } else {
                pendingNumber = numero
                pendingResult = result
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CALL_PHONE), 7041)
            }
        }
    }

    private fun llamar(numero: String, result: MethodChannel.Result) {
        try {
            startActivity(Intent(Intent.ACTION_CALL, Uri.fromParts("tel", numero, null)))
            result.success(null)
        } catch (e: Exception) {
            result.error("CALL_FAILED", "No se pudo iniciar la llamada en este dispositivo.", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 7041) return
        val result = pendingResult ?: return
        val numero = pendingNumber ?: ""
        pendingResult = null
        pendingNumber = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) llamar(numero, result)
        else result.error("PERMISSION_DENIED", "Permita las llamadas para usar este botón.", null)
    }
}
