# 🚀 LISTO PARA PROBAR - Shader Params N1 Convention

**Estado:** ✅ **IMPLEMENTACIÓN COMPLETA**  
**Fecha:** 2 de noviembre de 2025  
**Branch:** Shader-Refactor

---

## ✅ ¿Qué se hizo?

Se aplicaron **exitosamente** los 4 archivos completos con la convención **N1** (namespaced params por shader id):

1. ✅ `render/shader_stack.lua` - Core del sistema con inyección de params
2. ✅ `render/shaders/lighting/basic.lua` - Lee desde `params.basic`
3. ✅ `render/shaders/lighting/dynamic.lua` - Lee desde `params.dynamic` + exporta A2
4. ✅ `render/preview_renderer.lua` - Patch para inicialización de params

**Backups creados** (4 archivos) para seguridad ✅

---

## 📋 PRÓXIMO PASO: PROBAR

### 1️⃣ Cierra Aseprite completamente

Si está abierto, ciérralo del todo (no solo recarga la extensión).

### 2️⃣ Abre Aseprite y carga la extensión

Debería cargar normalmente. Verifica la consola (Window → Console):

```
✅ [AseVoxel] Shader loaded: basic (lighting)
✅ [AseVoxel] Shader loaded: dynamic (lighting)
✅ [AseVoxel] Loaded 2 lighting, X fx shaders
```

❌ **Si ves errores rojos**, lee la sección "Troubleshooting" más abajo.

### 3️⃣ Prueba los shaders

1. Abre un sprite con voxels
2. Abre AseVoxel Viewer (Extensions → AseVoxel)
3. Abre Shader Stack dialog
4. Mueve los sliders de "Basic" o "Dynamic"
5. **Verifica:** Los cambios se aplican en tiempo real sin errores

### 4️⃣ Revisa la consola

No deberías ver:
- ❌ "attempt to index nil value (params.X)"
- ❌ "shader_crash_"
- ❌ "shader_invalid_output"

Deberías ver (si todo OK):
- ✅ `[batch_success] Shader processing successful, 6 faces returned`

---

## 📖 Documentos de Referencia

Usa estos archivos según necesites:

1. **`IMPLEMENTATION_SUMMARY_N1.md`**  
   📄 Resumen ejecutivo de qué se hizo

2. **`SHADER_PARAMS_N1_APPLIED.md`**  
   🔧 Documentación técnica completa con detalles de implementación

3. **`QUICK_TEST_N1.md`**  
   ✅ Guía de testing paso a paso (5 tests específicos)

---

## 🐛 Troubleshooting

### ❌ "Extension won't load" / Errores de sintaxis

**Solución:** Restaurar backups
```powershell
cd "d:\Rezi\Documentos\AseVoxel"
Copy-Item "render\shader_stack.lua.backup" "render\shader_stack.lua" -Force
Copy-Item "render\shaders\lighting\basic.lua.backup" "render\shaders\lighting\basic.lua" -Force
Copy-Item "render\shaders\lighting\dynamic.lua.backup" "render\shaders\lighting\dynamic.lua" -Force
Copy-Item "render\preview_renderer.lua.backup" "render\preview_renderer.lua" -Force
```
Luego reinicia Aseprite.

### ❌ "Params don't work" / Sliders no cambian nada

**Solución:** Habilitar debug mode
1. Abre `render/shader_stack.lua`
2. Agrega en línea 1: `VERBOSE_SHADER_DEBUG = true`
3. Reinicia Aseprite
4. Verifica consola para mensajes `[SHADER_OK]` o `[SHADER_ERROR]`

### ❌ Errores de "nil params"

**Verifica:**
- ¿Se llama correctamente `shaderStack.execute(params.shaderStack, shaderData)`?
- ¿`preview_renderer.lua` tiene el patch aplicado?
- ¿Los shaders leen desde `shaderData.params[shaderId]`?

---

## 📊 Archivos Modificados vs Backups

| Archivo | Original | Modificado | Backup |
|---------|----------|------------|--------|
| `shader_stack.lua` | 11,096 bytes | 10,188 bytes | ✅ |
| `basic.lua` | 3,161 bytes | 3,470 bytes | ✅ |
| `dynamic.lua` | 7,223 bytes | 6,279 bytes | ✅ |
| `preview_renderer.lua` | 75,568 bytes | 76,416 bytes | ✅ |

Todos los archivos `.backup` están en sus carpetas originales.

---

## 🎯 Criterios de Éxito

Para considerar la implementación exitosa:

- [ ] Extension carga sin errores
- [ ] Shader Stack dialog se abre
- [ ] Sliders de `basic` responden (lightIntensity, shadeIntensity)
- [ ] Sliders de `dynamic` responden (pitch, yaw, diffuse, ambient, etc.)
- [ ] No hay errores de "nil params" en consola
- [ ] Render se ve correcto (no negro/blanco)

Si **TODOS** los criterios pasan → ✅ **IMPLEMENTACIÓN EXITOSA**

---

## 🔄 Si Todo Funciona

1. ✅ Commit los cambios al branch `Shader-Refactor`
2. ✅ Ahora puedes crear FX shaders que lean `_lastLightDir` y `params.dynamic`
3. ✅ La convención N1 está lista para escalar a más shaders

---

## 🆘 Si Algo Falla

1. No entres en pánico - tienes backups ✅
2. Lee el mensaje de error específico en consola
3. Busca el error en `SHADER_PARAMS_N1_APPLIED.md`
4. Si no puedes resolver, restaura backups y reporta el error

---

## 🎉 ¡Listo!

**Los 4 archivos están actualizados y listos.**  
**Los backups están seguros.**  
**La documentación está completa.**

**Ahora solo falta:** Probar en Aseprite 🚀

---

**Archivos importantes:**
- ✅ `IMPLEMENTATION_SUMMARY_N1.md` - ¿Qué se hizo?
- ✅ `SHADER_PARAMS_N1_APPLIED.md` - Detalles técnicos
- ✅ `QUICK_TEST_N1.md` - Cómo probar
- ✅ Este archivo - Guía rápida de inicio

**¡Buena suerte con las pruebas! 🎨**
