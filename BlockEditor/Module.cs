using System;
using System.Windows.Forms;
using Topomatic.ApplicationPlatform.Plugins;
using Topomatic.Cad.View;
using Topomatic.Cad.View.Hints;
using Topomatic.Controls.Dialogs;
using Topomatic.Dwg;
using Topomatic.Dwg.Layer;
using BlockEditor.Core;

namespace BlockEditor
{
    /// <summary>
    /// Модуль плагина «BlockEditor» — редактор блоков Topomatic Robur.
    ///
    /// Команды:
    ///   block_editor_edit   — открыть определение выбранного блока в отдельном окне
    ///                         чертежа; по закрытию окна перезаписать определение
    ///                         исходного блока (временный файл удаляется);
    ///   block_editor_save   — сохранить блок в отдельный файл (.dwp);
    ///   block_editor_rename — переименовать блок.
    ///
    /// Каркас — по AGENTS.md (internal partial Module : PluginInitializator,
    /// [cmd] коротким атрибутом, сообщения через MessageDlg).
    /// </summary>
    internal partial class Module : PluginInitializator
    {
        public override void Initialize(PluginFactory factory)
        {
            base.Initialize(factory);
        }

        /// <summary>Редактировать блок в отдельном окне чертежа.</summary>
        [cmd("block_editor_edit")]
        public void EditBlock(string prms)
        {
            try
            {
                var cadView = CadView;
                var drawing = BlockOps.FindActiveDrawing(cadView);
                if (drawing == null)
                {
                    MessageDlg.Show("Активный чертёж не найден.");
                    return;
                }

                var insert = BlockOps.PickInsert(cadView);
                if (insert == null)
                {
                    return; // выбор отменён
                }

                var block = BlockOps.GetInsertBlock(insert);
                if (block == null)
                {
                    MessageDlg.Show("Выбранный объект не является вставкой блока.");
                    return;
                }

                var existing = BlockEditSession.FindFor(block);
                if (existing != null)
                {
                    existing.Activate();
                    MessageDlg.Show("Блок «" + block.Name + "» уже открыт в редакторе.");
                    return;
                }

                var session = new BlockEditSession(drawing, block, cadView);
                session.OpenWindow();
            }
            catch (Exception ex)
            {
                MessageDlg.Show("Не удалось открыть редактор блока: " + ex.Message);
            }
        }

        /// <summary>Сохранить блок в отдельный файл (нативный .dwp).</summary>
        [cmd("block_editor_save")]
        public void SaveBlock(string prms)
        {
            try
            {
                var cadView = CadView;
                var drawing = BlockOps.FindActiveDrawing(cadView);
                if (drawing == null)
                {
                    MessageDlg.Show("Активный чертёж не найден.");
                    return;
                }

                var insert = BlockOps.PickInsert(cadView);
                if (insert == null)
                {
                    return; // выбор отменён
                }

                var block = BlockOps.GetInsertBlock(insert);
                if (block == null)
                {
                    MessageDlg.Show("Выбранный объект не является вставкой блока.");
                    return;
                }

                using (var dlg = new SaveFileDialog())
                {
                    dlg.Title = "Сохранить блок «" + block.Name + "»";
                    // Только нативный формат Robur: без потерь, не зависит от Acax-моста.
                    dlg.Filter = "Чертёж Robur (*.dwp)|*.dwp";
                    dlg.FileName = block.Name + ".dwp";
                    dlg.AddExtension = true;
                    dlg.DefaultExt = "dwp";

                    if (dlg.ShowDialog() != DialogResult.OK)
                    {
                        return;
                    }

                    BlockOps.SaveBlockToFile(block, dlg.FileName);
                    MessageDlg.Show("Блок «" + block.Name + "» сохранён в файл:\n" + dlg.FileName);
                }
            }
            catch (Exception ex)
            {
                MessageDlg.Show("Не удалось сохранить блок: " + ex.Message);
            }
        }

        /// <summary>Переименовать блок.</summary>
        [cmd("block_editor_rename")]
        public void RenameBlock(string prms)
        {
            try
            {
                var cadView = CadView;
                var drawing = BlockOps.FindActiveDrawing(cadView);
                if (drawing == null)
                {
                    MessageDlg.Show("Активный чертёж не найден.");
                    return;
                }

                var insert = BlockOps.PickInsert(cadView);
                if (insert == null)
                {
                    return; // выбор отменён
                }

                var block = BlockOps.GetInsertBlock(insert);
                if (block == null)
                {
                    MessageDlg.Show("Выбранный объект не является вставкой блока.");
                    return;
                }

                string newName = block.Name;
                var result = CadCursors.GetString(cadView, ref newName, "Новое имя блока");
                if (result != GetPointResult.Accept)
                {
                    return; // ввод отменён
                }

                string applied = BlockOps.RenameBlock(drawing, block, newName);
                cadView.Unlock();
                cadView.Invalidate();
                MessageDlg.Show("Блок переименован в «" + applied + "».");
            }
            catch (Exception ex)
            {
                MessageDlg.Show("Не удалось переименовать блок: " + ex.Message);
            }
        }
    }
}