using System;
using System.IO;
using Topomatic.Cad.View;
using Topomatic.FoundationClasses;
using Topomatic.Dwg;
using Topomatic.Dwg.Entities;
using Topomatic.Dwg.Layer;

namespace BlockEditor.Core
{
    /// <summary>
    /// Статические операции с чертежами и блоками (только подтверждённый API —
    /// см. ApiNotes/dwg.md, Tutorial11, декомпиляцию Topomatic.Dwg.Controller).
    /// </summary>
    internal static class BlockOps
    {
        /// <summary>Активный чертёж текущего видового экрана (или null).</summary>
        public static Drawing FindActiveDrawing(CadView cadView)
        {
            if (cadView == null) return null;
            var layer = DrawingLayer.GetDrawingLayer(cadView, false);
            return layer == null ? null : layer.Drawing;
        }

        /// <summary>
        /// Вставка блока для команды: если в текущем выделении ровно одна вставка —
        /// берём её; иначе предлагаем пользователю указать вставку на экране.
        /// </summary>
        public static DwgInsert PickInsert(CadView cadView)
        {
            if (cadView == null) return null;

            var single = GetSingleSelectedInsert(cadView);
            if (single != null) return single;

            if (cadView.SelectionSet == null) return null;
            var obj = cadView.SelectionSet.PickOneObjectAtScreen(o => o is DwgInsert, "Укажите вставку блока");
            return obj as DwgInsert;
        }

        private static DwgInsert GetSingleSelectedInsert(CadView cadView)
        {
            if (cadView.SelectionSet == null) return null;

            DwgInsert found = null;
            int count = 0;
            foreach (object o in cadView.SelectionSet)
            {
                if (o is DwgInsert)
                {
                    found = (DwgInsert)o;
                    count++;
                }
            }
            return count == 1 ? found : null;
        }

        /// <summary>Блок вставки. Свойство Block может бросить исключение на разорванной ссылке.</summary>
        public static DwgBlock GetInsertBlock(DwgInsert insert)
        {
            if (insert == null) return null;
            try
            {
                return insert.Block;
            }
            catch
            {
                return null;
            }
        }

        /// <summary>
        /// Временный чертёж — копия определения блока в пространство модели.
        /// ReferencesContext переразрешает ссылки на именованные объекты (слои,
        /// типы линий, вложенные блоки) относительно нового чертежа.
        /// </summary>
        public static Drawing CreateTempDrawing(DwgBlock block, string tempFile)
        {
            var drawing = new Drawing();
            drawing.Filename = tempFile;
            drawing.ActiveSpace.Entities.CopyFrom(block.Entities, new ReferencesContext(drawing));
            return drawing;
        }

        /// <summary>Запись бэкап-файла временного чертежа (не критично, если не удалось).</summary>
        public static void TryWriteBackup(Drawing drawing, string file)
        {
            try
            {
                var provider = Topomatic.Acax.Export.DrawingExportProvider.GetProvider(Path.GetExtension(file));
                if (provider == null)
                {
                    provider = Topomatic.Acax.Export.DrawingExportProvider.GetPreferedProvider();
                }
                if (provider != null)
                {
                    provider.SaveToFile(file, drawing);
                }
            }
            catch
            {
                // бэкап не критичен: правки читаются из памяти
            }
        }

        /// <summary>
        /// Перезапись определения блока содержимым чертежа-редактора.
        /// Вызывается внутри BeginUpdate/EndUpdate исходного чертежа.
        /// Clear()+CopyFrom обёрнуты в транзакцию блока: при исключении (например,
        /// битая ссылка в правке) определение откатывается к прежнему, а не остаётся
        /// пустым. Канон — TutorialEditAlignment (vertex.BeginTransaction/Commit/Rollback).
        /// </summary>
        public static void ApplyToBlock(Drawing sourceDrawing, DwgBlock block, Drawing editDrawing)
        {
            EnsureLayers(editDrawing, sourceDrawing);
            block.BeginTransaction();
            try
            {
                block.Entities.Clear();
                block.Entities.CopyFrom(editDrawing.ActiveSpace.Entities, new ReferencesContext(sourceDrawing));
                block.Commit();
            }
            catch
            {
                block.Rollback();
                throw;
            }
        }

        /// <summary>
        /// Слои чертежа-редактора, которых нет в целевом чертеже, переносим
        /// (имя + цвет + видимость), чтобы сущности блока не теряли слои.
        /// </summary>
        private static void EnsureLayers(Drawing from, Drawing to)
        {
            foreach (DwgLayer layer in from.Layers)
            {
                if (to.Layers[layer.Name] == null)
                {
                    var copy = to.Layers.Add(layer.Name);
                    copy.Color = layer.Color;
                    copy.Visible = layer.Visible;
                }
            }
        }

        /// <summary>
        /// Сохранить блок в отдельный файл — только нативный <c>.dwp</c>
        /// (Stg/BSTG, все сущности Robur без потерь, Acax-мост не нужен).
        /// Провайдер берётся по расширению — канон Class37 (tables_single_drawing):
        /// GetProvider(Path.GetExtension) → фолбэк GetPreferedProvider (тоже .dwp).
        /// </summary>
        public static void SaveBlockToFile(DwgBlock block, string file)
        {
            var drawing = CreateTempDrawing(block, file);

            var provider = Topomatic.Acax.Export.DrawingExportProvider.GetProvider(Path.GetExtension(file));
            if (provider == null)
            {
                provider = Topomatic.Acax.Export.DrawingExportProvider.GetPreferedProvider();
            }
            if (provider == null)
            {
                throw new InvalidOperationException("Не найден провайдер экспорта чертежей.");
            }
            provider.SaveToFile(file, drawing);
        }

        /// <summary>
        /// Переименование блока штатным путём: сеттер Name (так делает штатный диалог
        /// RenameSystemTablesDlg из Topomatic.Dwg.Controller).
        /// </summary>
        public static string RenameBlock(Drawing drawing, DwgBlock block, string newName)
        {
            newName = newName == null ? string.Empty : newName.Trim();
            if (newName.Length == 0)
            {
                throw new ArgumentException("Имя блока не может быть пустым.");
            }
            if (newName == block.Name)
            {
                return block.Name; // имя не изменилось
            }
            if (drawing.Blocks.IsExists(newName))
            {
                throw new ArgumentException("Блок с именем «" + newName + "» уже существует.");
            }
            if (!DrawingConsts.ValidName(newName, drawing.Blocks.NameType))
            {
                throw new ArgumentException("Имя «" + newName + "» недопустимо для блока.");
            }

            drawing.BeginUpdate();
            try
            {
                block.Name = newName;
            }
            finally
            {
                drawing.EndUpdate();
            }
            return block.Name;
        }

        /// <summary>
        /// Сколько вставок блока в текущем пространстве чертежа.
        /// Блок без вставок удалять бессмысленно — это отсекает опцию в диалоге.
        /// </summary>
        public static int CountInserts(Drawing drawing, DwgBlock block)
        {
            int count = 0;
            foreach (DwgEntity entity in drawing.ActiveSpace.Entities)
            {
                if (entity is DwgInsert insert && insert.Block == block)
                {
                    count++;
                }
            }
            return count;
        }

        /// <summary>
        /// Удаление определения блока из модели. Канон — robur-mcp (BlockTools.RemoveBlock):
        /// drawing.Blocks.Remove(name) внутри BeginUpdate/EndUpdate.
        /// </summary>
        public static void RemoveBlock(Drawing drawing, DwgBlock block, bool withInserts)
        {
            string name = block.Name;

            drawing.BeginUpdate();
            try
            {
                if (withInserts)
                {
                    // вставки удаляем первыми — иначе ссылки на блок осиротеют
                    // (ActiveSpace — это DwgBlock, коллекция сущностей в .Entities)
                    foreach (DwgEntity entity in drawing.ActiveSpace.Entities)
                    {
                        if (entity is DwgInsert insert && insert.Block == block)
                        {
                            drawing.ActiveSpace.Entities.Remove(insert);
                        }
                    }
                }
                if (!drawing.Blocks.Remove(name))
                {
                    throw new InvalidOperationException("Не удалось удалить блок «" + name + "».");
                }
            }
            finally
            {
                drawing.EndUpdate();
            }
        }
    }
}