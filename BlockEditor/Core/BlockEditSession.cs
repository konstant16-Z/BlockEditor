using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Forms;
using Topomatic.ApplicationPlatform;
using Topomatic.Cad.View;
using Topomatic.Controls.Dialogs;
using Topomatic.Dwg;
using Topomatic.Dwg.Layer;

namespace BlockEditor.Core
{
    /// <summary>
    /// Сессия редактирования блока:
    ///   • временный чертёж (копия определения блока) показывается в окне-редакторе
    ///     (эталон — [cmd("open_dwg_cmp")] из Topomatic.Dwg.Controller);
    ///   • все правки пользователя штатными командами чертежа пишутся напрямую
    ///     во временный чертёж в памяти (DwgController мутирует drawing пространства);
    ///   • по закрытию окна пользователю предлагается применить изменения к исходному
    ///     определению блока («дождаться правок → перезаписать блок»);
    ///   • временный файл (.dwp) создаётся как бэкап и удаляется по завершении сессии.
    /// </summary>
    internal sealed class BlockEditSession
    {
        private static readonly List<BlockEditSession> s_active = new List<BlockEditSession>();

        private readonly Drawing _sourceDrawing; // чертёж, в котором живёт блок
        private readonly DwgBlock _block;        // исходное определение блока
        private readonly Drawing _editDrawing;   // временный чертёж-редактор
        private readonly string _tempFile;       // бэкап-файл (.dwp)
        private readonly CadView _sourceCadView; // для обновления экрана после применения

        private IDocumentWindow _window;
        private bool _applied;

        public BlockEditSession(Drawing sourceDrawing, DwgBlock block, CadView sourceCadView)
        {
            _sourceDrawing = sourceDrawing;
            _block = block;
            _sourceCadView = sourceCadView;

            _tempFile = Path.Combine(Path.GetTempPath(), "RoburBlockEdit_" + Guid.NewGuid().ToString("N") + ".dwp");
            _editDrawing = BlockOps.CreateTempDrawing(block, _tempFile);

            // Бэкап определения на диске; неудача не критична — правки читаются из памяти
            BlockOps.TryWriteBackup(_editDrawing, _tempFile);
        }

        public string TempFile
        {
            get { return _tempFile; }
        }

        /// <summary>Активная сессия для данного блока (не более одной на блок).</summary>
        public static BlockEditSession FindFor(DwgBlock block)
        {
            foreach (var session in s_active)
            {
                if (ReferenceEquals(session._block, block))
                {
                    return session;
                }
            }
            return null;
        }

        public void Activate()
        {
            if (_window != null)
            {
                _window.Activate();
            }
        }

        /// <summary>
        /// Создаёт окно-редактор по эталону open_dwg_cmp и подписывается на закрытие.
        /// </summary>
        public void OpenWindow()
        {
            var project = ApplicationHost.Current.ActiveProject;
            if (project == null)
            {
                throw new InvalidOperationException("Нет активного проекта.");
            }

            string key = "DWG_BLOCK_EDIT_" + Guid.NewGuid().ToString("N");
            string type = "DWG_BLOCK_EDIT";
            var window = project.AddDocumentWindow(key, type, false) as IFramableDocumentWindow;
            if (window == null)
            {
                throw new InvalidOperationException("Не удалось создать окно чертежа.");
            }

            window.Text = "Редактор блока: " + _block.Name;
            if (!window.Contains(Consts.ModelFrame))
            {
                window.AddCadViewFrame(Consts.ModelFrame, "Модель");
            }

            var frame = window[Consts.ModelFrame];
            var layer = DrawingLayer.GetDrawingLayer(frame.CadView, true);
            if (layer == null)
            {
                layer = new DrawingLayer();
                layer.Enable = true; // окно редактируемое (в отличие от compare-окна)
                frame.CadView.AddLayer(layer);
            }
            layer.Drawing = _editDrawing;

            frame.CadView.SolveLimits(false);
            frame.CadView.Unlock();
            frame.CadView.Invalidate();

            _window = window;
            s_active.Add(this);
            window.FormClosing += OnWindowClosing;
            window.Activate();
        }

        /// <summary>
        /// «Дождались правок»: окно закрывается — спрашиваем, применить ли изменения
        /// к исходному определению блока. Временный файл удаляется.
        /// </summary>
        private void OnWindowClosing(object sender, FormClosingEventArgs e)
        {
            if (_applied)
            {
                return;
            }
            _applied = true;

            var result = MessageDlg.Show(
                "Применить изменения блока «" + _block.Name + "»?",
                MessageBoxButtons.YesNoCancel,
                MessageBoxIcon.Question);

            if (result == DialogResult.Cancel)
            {
                // Пользователь передумал закрывать — окно остаётся, файл не трогаем
                _applied = false;
                e.Cancel = true;
                return;
            }

            if (result == DialogResult.Yes)
            {
                ApplyToSourceBlock();
            }
            else
            {
                MessageDlg.Show("Изменения блока «" + _block.Name + "» не применены.");
            }

            DeleteTempFile();
            s_active.Remove(this);
        }

        private void ApplyToSourceBlock()
        {
            try
            {
                _sourceDrawing.BeginUpdate();
                try
                {
                    BlockOps.ApplyToBlock(_sourceDrawing, _block, _editDrawing);
                }
                finally
                {
                    _sourceDrawing.EndUpdate();
                }

                if (_sourceCadView != null)
                {
                    _sourceCadView.Unlock();
                    _sourceCadView.Invalidate();
                }
                MessageDlg.Show("Определение блока «" + _block.Name + "» обновлено.");
            }
            catch (Exception ex)
            {
                MessageDlg.Show("Не удалось применить изменения блока: " + ex.Message);
            }
        }

        private void DeleteTempFile()
        {
            try
            {
                if (File.Exists(_tempFile))
                {
                    File.Delete(_tempFile);
                }
            }
            catch
            {
                // файл останется в TEMP — не критично
            }
        }
    }
}