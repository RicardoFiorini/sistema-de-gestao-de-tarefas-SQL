-- 1. Configurações Globais e Criação
-- Forçamos utf8mb4 para garantir compatibilidade total (emojis, caracteres asiáticos, etc)
CREATE DATABASE IF NOT EXISTS GerenciamentoTarefas
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE GerenciamentoTarefas;

-- 2. Tabela de Usuários (Com Soft Delete e Rastreamento)
CREATE TABLE Usuarios (
    usuario_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    senha_hash VARCHAR(255) NOT NULL COMMENT 'Hash Argon2 ou Bcrypt',
    ativo BOOLEAN DEFAULT TRUE,
    ultimo_login DATETIME DEFAULT NULL,
    data_criacao DATETIME DEFAULT CURRENT_TIMESTAMP,
    data_atualizacao DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deletado_em DATETIME DEFAULT NULL, -- Soft Delete: O dado nunca é apagado fisicamente
    
    INDEX idx_email_ativo (email, ativo) -- Índice composto para login rápido
);

-- 3. Tabela de Categorias (Global e Personalizada)
CREATE TABLE Categorias (
    categoria_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    cor_hex VARCHAR(7) DEFAULT '#808080', -- Para renderização no Frontend
    descricao TINYTEXT,
    usuario_id INT DEFAULT NULL COMMENT 'NULL = Categoria Global do Sistema',
    ativo BOOLEAN DEFAULT TRUE,
    
    FOREIGN KEY (usuario_id) REFERENCES Usuarios(usuario_id) ON DELETE CASCADE,
    UNIQUE KEY uk_categoria_usuario (nome, usuario_id) -- Evita nomes duplicados para o mesmo usuário
);

-- 4. Tabela de Tarefas (Expandida com Prioridade e Prazos)
CREATE TABLE Tarefas (
    tarefa_id INT AUTO_INCREMENT PRIMARY KEY,
    usuario_id INT NOT NULL,
    categoria_id INT,
    titulo VARCHAR(200) NOT NULL,
    descricao TEXT,
    prioridade ENUM('Baixa', 'Media', 'Alta', 'Urgente') DEFAULT 'Media',
    status ENUM('Pendente', 'Em Andamento', 'Concluída', 'Cancelada') DEFAULT 'Pendente',
    data_vencimento DATETIME DEFAULT NULL,
    data_conclusao DATETIME DEFAULT NULL,
    data_criacao DATETIME DEFAULT CURRENT_TIMESTAMP,
    data_atualizacao DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deletado_em DATETIME DEFAULT NULL, -- Soft Delete
    
    FOREIGN KEY (usuario_id) REFERENCES Usuarios(usuario_id) ON DELETE CASCADE,
    FOREIGN KEY (categoria_id) REFERENCES Categorias(categoria_id) ON DELETE SET NULL,
    
    -- Índices Estratégicos (Composite Indexes)
    INDEX idx_busca_tarefas (usuario_id, status, data_vencimento), -- Otimiza a query mais comum (dashboard)
    FULLTEXT idx_texto_tarefa (titulo, descricao) -- Permite busca textual performática (MATCH AGAINST)
);

-- 5. Tabela de Histórico de Auditoria (Log de Alterações)
-- Um requisito Sênior: saber O QUE mudou e QUANDO.
CREATE TABLE TarefasLog (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    tarefa_id INT NOT NULL,
    status_anterior VARCHAR(20),
    status_novo VARCHAR(20),
    data_alteracao DATETIME DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (tarefa_id) REFERENCES Tarefas(tarefa_id) ON DELETE CASCADE
);

-- =========================================================
-- 🧠 LÓGICA DE NEGÓCIO (VIEWS, TRIGGERS, FUNCTIONS, PROCS)
-- =========================================================

-- VIEW 1: Dashboard Operacional (Join Otimizado)
-- Traz apenas dados ativos e formata visualmente o atraso
CREATE OR REPLACE VIEW v_DashboardTarefas AS
SELECT 
    t.tarefa_id,
    t.titulo,
    c.nome AS categoria,
    c.cor_hex AS categoria_cor,
    t.prioridade,
    t.status,
    t.data_vencimento,
    CASE 
        WHEN t.data_vencimento < NOW() AND t.status NOT IN ('Concluída', 'Cancelada') THEN 'ATRASADA'
        WHEN t.data_vencimento BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL 24 HOUR) THEN 'URGENTE'
        ELSE 'NO PRAZO' 
    END AS situacao_prazo,
    u.nome AS dono_tarefa
FROM Tarefas t
JOIN Usuarios u ON t.usuario_id = u.usuario_id
LEFT JOIN Categorias c ON t.categoria_id = c.categoria_id
WHERE t.deletado_em IS NULL AND u.deletado_em IS NULL;

-- VIEW 2: Relatório de Produtividade (Analytics)
CREATE OR REPLACE VIEW v_RelatorioProdutividade AS
SELECT 
    u.nome,
    COUNT(t.tarefa_id) AS total_tarefas,
    SUM(CASE WHEN t.status = 'Concluída' THEN 1 ELSE 0 END) AS concluidas,
    -- Cálculo de eficiência em porcentagem
    ROUND((SUM(CASE WHEN t.status = 'Concluída' THEN 1 ELSE 0 END) / COUNT(t.tarefa_id)) * 100, 2) AS taxa_eficiencia,
    -- Tempo médio de conclusão (em horas) para tarefas finalizadas
    ROUND(AVG(TIMESTAMPDIFF(HOUR, t.data_criacao, t.data_conclusao)), 1) AS media_horas_conclusao
FROM Usuarios u
JOIN Tarefas t ON u.usuario_id = t.usuario_id
WHERE t.deletado_em IS NULL AND t.status = 'Concluída'
GROUP BY u.usuario_id;

-- TRIGGER: Auditoria Automática e Atualização de Conclusão
DELIMITER //
CREATE TRIGGER trg_Tarefas_Audit_Update
BEFORE UPDATE ON Tarefas
FOR EACH ROW
BEGIN
    -- 1. Lógica de Data de Conclusão
    IF NEW.status = 'Concluída' AND OLD.status != 'Concluída' THEN
        SET NEW.data_conclusao = NOW();
    ELSEIF NEW.status != 'Concluída' THEN
        SET NEW.data_conclusao = NULL; -- Reseta se reabrir a tarefa
    END IF;

    -- 2. Inserção no Log de Auditoria (Apenas se o status mudou)
    IF OLD.status != NEW.status THEN
        INSERT INTO TarefasLog (tarefa_id, status_anterior, status_novo)
        VALUES (OLD.tarefa_id, OLD.status, NEW.status);
    END IF;
END //
DELIMITER ;

-- STORED PROCEDURE: Criar Tarefa com Validação (Encapsulamento)
-- O Backend chama apenas isso, não faz INSERT direto.
DELIMITER //
CREATE PROCEDURE sp_CriarNovaTarefa(
    IN p_usuario_id INT,
    IN p_categoria_id INT,
    IN p_titulo VARCHAR(200),
    IN p_descricao TEXT,
    IN p_prioridade VARCHAR(20),
    IN p_dias_para_vencer INT
)
BEGIN
    DECLARE v_data_vencimento DATETIME;
    
    -- Validação básica
    IF p_titulo IS NULL OR p_titulo = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Erro: Título é obrigatório.';
    END IF;

    -- Lógica de Data
    SET v_data_vencimento = DATE_ADD(NOW(), INTERVAL p_dias_para_vencer DAY);

    -- Inserção
    INSERT INTO Tarefas (usuario_id, categoria_id, titulo, descricao, prioridade, data_vencimento)
    VALUES (p_usuario_id, p_categoria_id, p_titulo, p_descricao, IFNULL(p_prioridade, 'Media'), v_data_vencimento);
    
    -- Retorna o ID criado (útil para APIs)
    SELECT LAST_INSERT_ID() AS nova_tarefa_id;
END //
DELIMITER ;
