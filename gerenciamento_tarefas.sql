-- Criação do banco de dados
CREATE DATABASE GerenciamentoTarefas;
USE GerenciamentoTarefas;

-- Tabela para armazenar informações dos usuários
CREATE TABLE Usuarios (
    usuario_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    senha VARCHAR(255) NOT NULL,
    data_criacao DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tabela para armazenar categorias de tarefas
CREATE TABLE Categorias (
    categoria_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    descricao TEXT
);

-- Tabela para armazenar tarefas
CREATE TABLE Tarefas (
    tarefa_id INT AUTO_INCREMENT PRIMARY KEY,
    usuario_id INT NOT NULL,
    categoria_id INT,
    titulo VARCHAR(200) NOT NULL,
    descricao TEXT,
    status ENUM('Pendente', 'Concluída') DEFAULT 'Pendente',
    data_criacao DATETIME DEFAULT CURRENT_TIMESTAMP,
    data_conclusao DATETIME,
    FOREIGN KEY (usuario_id) REFERENCES Usuarios(usuario_id) ON DELETE CASCADE,
    FOREIGN KEY (categoria_id) REFERENCES Categorias(categoria_id) ON DELETE SET NULL
);

-- Índices para melhorar a performance
CREATE INDEX idx_usuario_email ON Usuarios(email);
CREATE INDEX idx_categoria_nome ON Categorias(nome);
CREATE INDEX idx_tarefa_usuario ON Tarefas(usuario_id);
CREATE INDEX idx_tarefa_categoria ON Tarefas(categoria_id);
CREATE INDEX idx_tarefa_status ON Tarefas(status);

-- View para listar todas as tarefas com informações do usuário e categoria
CREATE VIEW ViewTarefas AS
SELECT t.tarefa_id, t.titulo, t.descricao, t.status, u.nome AS usuario, c.nome AS categoria, 
       t.data_criacao, t.data_conclusao
FROM Tarefas t
JOIN Usuarios u ON t.usuario_id = u.usuario_id
LEFT JOIN Categorias c ON t.categoria_id = c.categoria_id;

-- Função para contar tarefas pendentes por usuário
DELIMITER //
CREATE FUNCTION ContarTarefasPendentes(usuarioId INT) RETURNS INT
BEGIN
    DECLARE qtd INT;
    SELECT COUNT(*) INTO qtd FROM Tarefas WHERE usuario_id = usuarioId AND status = 'Pendente';
    RETURN qtd;
END //
DELIMITER ;

-- Função para contar tarefas concluídas por usuário
DELIMITER //
CREATE FUNCTION ContarTarefasConcluidas(usuarioId INT) RETURNS INT
BEGIN
    DECLARE qtd INT;
    SELECT COUNT(*) INTO qtd FROM Tarefas WHERE usuario_id = usuarioId AND status = 'Concluída';
    RETURN qtd;
END //
DELIMITER ;

-- Trigger para atualizar a data de conclusão ao marcar a tarefa como concluída
DELIMITER //
CREATE TRIGGER Trigger_AposConcluirTarefa
BEFORE UPDATE ON Tarefas
FOR EACH ROW
BEGIN
    IF NEW.status = 'Concluída' AND OLD.status != 'Concluída' THEN
        SET NEW.data_conclusao = NOW();
    END IF;
END //
DELIMITER ;

-- Trigger para impedir a exclusão de usuários com tarefas pendentes
DELIMITER //
CREATE TRIGGER Trigger_AntesExcluirUsuario
BEFORE DELETE ON Usuarios
FOR EACH ROW
BEGIN
    DECLARE qtd INT;
    SELECT COUNT(*) INTO qtd FROM Tarefas WHERE usuario_id = OLD.usuario_id AND status = 'Pendente';
    IF qtd > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Não é possível excluir o usuário com tarefas pendentes.';
    END IF;
END //
DELIMITER ;

-- Inserção de exemplo de usuários
INSERT INTO Usuarios (nome, email, senha) VALUES 
('Carlos Silva', 'carlos@example.com', 'senha1'),
('Ana Costa', 'ana@example.com', 'senha2');

-- Inserção de exemplo de categorias
INSERT INTO Categorias (nome, descricao) VALUES 
('Trabalho', 'Tarefas relacionadas ao trabalho.'),
('Pessoal', 'Tarefas do dia a dia.');

-- Inserção de exemplo de tarefas
INSERT INTO Tarefas (usuario_id, categoria_id, titulo, descricao) VALUES 
(1, 1, 'Preparar Relatório', 'Preparar o relatório mensal para a reunião.'),
(1, 2, 'Comprar Mantimentos', 'Ir ao mercado e comprar mantimentos.'),
(2, 1, 'Atualizar Projeto', 'Atualizar o status do projeto no sistema.');

-- Selecionar todas as tarefas
SELECT * FROM ViewTarefas;

-- Selecionar contagem de tarefas pendentes para um usuário específico
SELECT ContarTarefasPendentes(1) AS tarefas_pendentes_usuario_1;

-- Selecionar contagem de tarefas concluídas para um usuário específico
SELECT ContarTarefasConcluidas(1) AS tarefas_concluidas_usuario_1;

-- Atualizar o status de uma tarefa para concluída
UPDATE Tarefas SET status = 'Concluída' WHERE tarefa_id = 1;

-- Excluir uma categoria (lembrando que tarefas relacionadas a essa categoria não serão excluídas)
DELETE FROM Categorias WHERE categoria_id = 1;

-- Excluir um usuário (isso falhará se o usuário tiver tarefas pendentes)
DELETE FROM Usuarios WHERE usuario_id = 1;
