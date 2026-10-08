using System;
using Topomatic.ApplicationPlatform.Plugins;

namespace BlockEditor
{
    /// <summary>
    /// Публичный хост плагина. Возвращает типы модулей ядру Robur
    /// (обязателен: см. структуру .plugin — assembly "BlockEditor.dll, BlockEditor.ModulePluginHost").
    /// </summary>
    public class ModulePluginHost : PluginHostInitializator
    {
        protected override Type[] GetTypes()
        {
            return new Type[] { typeof(Module) };
        }
    }
}