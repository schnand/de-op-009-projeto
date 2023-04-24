
import psycopg2
import os
import boto3
import pandas as pd
from io import StringIO

print("Import concluído");

# Crie uma sessão do boto3 com as suas credenciais ou configure suas variáveis de ambiente.
s3 = boto3.client('s3')

def lambda_metodo(event, context):

    # Nome do bucket e do arquivo
    bucket_name = os.environ['BUCKET_NAME']
    file_name = 'train.csv'

    print(bucket_name)
    print(file_name)

    print("Lendo o arquivo csv no s3");

    # Lendo o arquivo CSV do S3
    obj = s3.get_object(Bucket=bucket_name, Key=file_name)
    data = obj['Body'].read().decode('utf-8')

    print("transformando em um dataframe");

    # Transformando o arquivo em um dataframe
    df_titanic = pd.read_csv(StringIO(data))

    df_titanic.head()

    len(df_titanic)

    print("Realizando a conexão com o banco de dados");

    # Realizando a conexão com o banco de dados usando as variáveis de ambiente
    conn = psycopg2.connect(
        host=os.environ['DATABASE_HOST'],
        port=os.environ['DATABASE_PORT'],
        database=os.environ['DATABASE_NAME'],
        user=os.environ['DATABASE_USERNAME'],
        password=os.environ['DATABASE_PASSWORD']
    )

    print("Criando a tabela titanic");

    # Criando uma tabela chamada titanic no database postgres
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE titanic (
            survived INTEGER,
            sex TEXT,
            age INTEGER,
            n_siblings_spouses INTEGER,
            parch INTEGER,
            fare FLOAT,
            class TEXT,
            deck TEXT,
            embark_town	 TEXT,
            alone TEXT
            
        )
    ''')

    print("Gravando o conteúdo do dataframe df_titanic na tabela titanic");

    # Gravando o conteúdo do dataframe df_titanic na tabela titanic
    for index, row in df_titanic.iterrows():
        cur.execute('''
            INSERT INTO titanic (
                survived,sex,age, n_siblings_spouses, parch, fare, class, deck, embark_town,alone
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
        ''', (
            row['survived'], row['sex'], row['age'], row['n_siblings_spouses'], row['parch'],
            row['fare'], row['class'], row['deck'], row['embark_town'], row['alone']
        ))


    df_select_titanic = pd.read_sql_query('SELECT * FROM titanic', conn)

    print(df_select_titanic.head())

    print(df_select_titanic.shape)

    print("Finalizando a transação e fechando a conexão");
    # Finalizando a transação e fechando a conexão
    conn.commit()
    cur.close()
    conn.close()
