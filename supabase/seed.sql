-- Mercatto seed generated from EA Ratings
begin;

-- Teams
insert into teams (name, crest_url) values ('Liverpool', 'https://drop-assets.ea.com/images/3mmzooNXBDCKuCy6kWcGQo/2e332a30fe2a7225a88fcb1898f48bbf/l9.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('FC Barcelona', 'https://drop-assets.ea.com/images/5VXhqALaBzgvb2YG8iJxlq/990024f3e3ecc9e6c37eae41ebef86bd/l241.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Real Madrid', 'https://drop-assets.ea.com/images/Pk8nYrWuRt895RlhJx8jI/445d98b711f413a3a1e70c41b19b0f95/l243.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Man Utd', 'https://drop-assets.ea.com/images/5xxJeUfFY6FEQZEJyJK35/990979becf88b88ecb6461dc441c2ebf/l11.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Manchester City', 'https://drop-assets.ea.com/images/4asmNLic4aQn6cjlEg1t5u/88bea3ddd6c1f620bbf813041f248685/l10.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Arsenal', 'https://drop-assets.ea.com/images/2ng99bvkwKaA228PJje39i/09d2df89a78377d3f8d3f78469cbadc9/l1.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Spurs', 'https://drop-assets.ea.com/images/7kUcyCh5xGrzQlcjP2Q9NH/11aba507486f44765ee5938b1b5b097e/l18.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Juventus', 'https://drop-assets.ea.com/images/6zWQmPATtK8lpsiXbKb3mY/6b2d1dab08ef14f63271a5cd70a0db0d/l45.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Milano FC', 'https://drop-assets.ea.com/images/6D3s1RlLRER3UOunC4Lofv/ec87a4178160a87521b0b7c688e7638e/l131681.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Lombardia FC', 'https://drop-assets.ea.com/images/1thPMvXN97JgFvt6ASWr4c/d2ca0a691a98c344305bc0975ab70314/l131682.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('SSC Napoli', 'https://drop-assets.ea.com/images/2FIV26KpnSXl3Nv8Ar6jk3/d8461aa150da3d433fccc34bc80c978f/l48.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('FC Bayern München', 'https://drop-assets.ea.com/images/3p0dv1pGWIH6lGAKZssZKH/4f70d2c5a3c147f3e006c863e85e4993/l21.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Leverkusen', 'https://drop-assets.ea.com/images/mGqQw1um1ucUAshcK0Eop/9c7fe656f526c98b217ff2a052377b5c/l32.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Borussia Dortmund', 'https://drop-assets.ea.com/images/TmqxUZk2FrbFXOK1kdE89/3dce225926ac7cfd9f283ecd731fa710/l22.png') on conflict (name) do update set crest_url = excluded.crest_url;
insert into teams (name, crest_url) values ('Atlético de Madrid', 'https://drop-assets.ea.com/images/vYcueolPvaGx8blMqhPZ5/5dc3479fc8b85d475fd980c53fc2056f/l240.png') on conflict (name) do update set crest_url = excluded.crest_url;

-- Players
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mohamed Salah', 91, 'MD', 'Egipto', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p209331.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p209331.png?padding=0.7' where name = 'Mohamed Salah' and ovr = 91 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Virgil van Dijk', 90, 'DFC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p203376.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p203376.png?padding=0.7' where name = 'Virgil van Dijk' and ovr = 90 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alisson Ramses Becker', 89, 'POR', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212831.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212831.png?padding=0.7' where name = 'Alisson Ramses Becker' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Florian Wirtz', 89, 'MCO', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256630.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256630.png?padding=0.7' where name = 'Florian Wirtz' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alexander Isak', 88, 'DC', 'Suecia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233731.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233731.png?padding=0.7' where name = 'Alexander Isak' and ovr = 88 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alexis Mac Allister', 87, 'MC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239837.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239837.png?padding=0.7' where name = 'Alexis Mac Allister' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ibrahima Konaté', 86, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237678.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237678.png?padding=0.7' where name = 'Ibrahima Konaté' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ryan Gravenberch', 85, 'MCD', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246104.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246104.png?padding=0.7' where name = 'Ryan Gravenberch' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Giorgi Mamardashvili', 84, 'POR', 'Georgia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p262621.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p262621.png?padding=0.7' where name = 'Giorgi Mamardashvili' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Cody Gakpo', 84, 'MI', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p242516.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p242516.png?padding=0.7' where name = 'Cody Gakpo' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Dominik Szoboszlai', 83, 'MCO', 'Hungría', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236772.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236772.png?padding=0.7' where name = 'Dominik Szoboszlai' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jeremie Frimpong', 83, 'LD', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253149.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253149.png?padding=0.7' where name = 'Jeremie Frimpong' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Hugo Ekitiké', 83, 'DC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257289.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257289.png?padding=0.7' where name = 'Hugo Ekitiké' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Milos Kerkez', 82, 'LI', 'Hungría', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p260908.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p260908.png?padding=0.7' where name = 'Milos Kerkez' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Andrew Robertson', 82, 'LI', 'Escocia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216267.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216267.png?padding=0.7' where name = 'Andrew Robertson' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Federico Chiesa', 81, 'MD', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235805.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235805.png?padding=0.7' where name = 'Federico Chiesa' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Curtis Jones', 80, 'MCO', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p242434.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p242434.png?padding=0.7' where name = 'Curtis Jones' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Wataru Endo', 79, 'MCD', 'Japón', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232487.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232487.png?padding=0.7' where name = 'Wataru Endo' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Joe Gomez', 79, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225100.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225100.png?padding=0.7' where name = 'Joe Gomez' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Conor Bradley', 78, 'LD', 'Irlanda del N.', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264298.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264298.png?padding=0.7' where name = 'Conor Bradley' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Stefan Bajcetic Maquieira', 73, 'MCD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p271975.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p271975.png?padding=0.7' where name = 'Stefan Bajcetic Maquieira' and ovr = 73 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Freddie Woodman', 71, 'POR', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p222514.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p222514.png?padding=0.7' where name = 'Freddie Woodman' and ovr = 71 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Giovanni Leoni', 69, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p70824.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p70824.png?padding=0.7' where name = 'Giovanni Leoni' and ovr = 69 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rio Ngumoha', 68, 'MI', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p80376.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p80376.png?padding=0.7' where name = 'Rio Ngumoha' and ovr = 68 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Calvin Ramsay', 65, 'LD', 'Escocia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p252897.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p252897.png?padding=0.7' where name = 'Calvin Ramsay' and ovr = 65 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ármin Pécsi', 64, 'POR', 'Hungría', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p79922.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p79922.png?padding=0.7' where name = 'Ármin Pécsi' and ovr = 64 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Trey Nyoni', 64, 'MC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p279128.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p279128.png?padding=0.7' where name = 'Trey Nyoni' and ovr = 64 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rhys Williams', 61, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247601.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247601.png?padding=0.7' where name = 'Rhys Williams' and ovr = 61 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Raphael Dias Belloli', 89, 'MI', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233419.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233419.png?padding=0.7' where name = 'Raphael Dias Belloli' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Lamine Yamal Nasraoui Ebana', 89, 'MD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277643.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277643.png?padding=0.7' where name = 'Lamine Yamal Nasraoui Ebana' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pedro González López', 89, 'MC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251854.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251854.png?padding=0.7' where name = 'Pedro González López' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Robert Lewandowski', 88, 'DC', 'Polonia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p188545.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p188545.png?padding=0.7' where name = 'Robert Lewandowski' and ovr = 88 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Frenkie de Jong', 87, 'MC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p228702.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p228702.png?padding=0.7' where name = 'Frenkie de Jong' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jules Koundé', 87, 'LD', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241486.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241486.png?padding=0.7' where name = 'Jules Koundé' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marc-André ter Stegen', 86, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192448.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192448.png?padding=0.7' where name = 'Marc-André ter Stegen' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Daniel Olmo Carvajal', 85, 'MCO', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p244260.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p244260.png?padding=0.7' where name = 'Daniel Olmo Carvajal' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Wojciech Szczęsny', 84, 'POR', 'Polonia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p186153.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p186153.png?padding=0.7' where name = 'Wojciech Szczęsny' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Joan García Pons', 83, 'POR', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259532.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259532.png?padding=0.7' where name = 'Joan García Pons' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pablo Martín Páez Gavira', 83, 'MC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264240.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264240.png?padding=0.7' where name = 'Pablo Martín Páez Gavira' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alejandro Balde Martínez', 83, 'LI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p263578.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p263578.png?padding=0.7' where name = 'Alejandro Balde Martínez' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ferran Torres García', 83, 'EI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241461.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241461.png?padding=0.7' where name = 'Ferran Torres García' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ronald Araujo', 83, 'DFC', 'Uruguay', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253163.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253163.png?padding=0.7' where name = 'Ronald Araujo' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pau Cubarsí Paredes', 82, 'DFC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278046.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278046.png?padding=0.7' where name = 'Pau Cubarsí Paredes' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Fermín López Marín', 80, 'MCO', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277179.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277179.png?padding=0.7' where name = 'Fermín López Marín' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marcus Rashford', 80, 'MI', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231677.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231677.png?padding=0.7' where name = 'Marcus Rashford' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Andreas Christensen', 80, 'DFC', 'Dinamarca', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p213661.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p213661.png?padding=0.7' where name = 'Andreas Christensen' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marc Casadó Torras', 79, 'MCD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272600.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272600.png?padding=0.7' where name = 'Marc Casadó Torras' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Eric García Martret', 79, 'DFC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245037.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245037.png?padding=0.7' where name = 'Eric García Martret' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Gerard Martín Langreo', 74, 'LI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74462.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74462.png?padding=0.7' where name = 'Gerard Martín Langreo' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marc Bernal Casas', 73, 'MCD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74463.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74463.png?padding=0.7' where name = 'Marc Bernal Casas' and ovr = 73 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Roony Bardghji', 69, 'MD', 'Suecia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p265600.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p265600.png?padding=0.7' where name = 'Roony Bardghji' and ovr = 69 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kylian Mbappé', 91, 'DC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231747.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231747.png?padding=0.7' where name = 'Kylian Mbappé' and ovr = 91 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jude Bellingham', 90, 'MCO', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p252371.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p252371.png?padding=0.7' where name = 'Jude Bellingham' and ovr = 90 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Federico Valverde', 89, 'MC', 'Uruguay', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239053.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239053.png?padding=0.7' where name = 'Federico Valverde' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Vinícius José de Oliveira Júnior', 89, 'EI', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p238794.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p238794.png?padding=0.7' where name = 'Vinícius José de Oliveira Júnior' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Thibaut Courtois', 89, 'POR', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192119.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192119.png?padding=0.7' where name = 'Thibaut Courtois' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Antonio Rüdiger', 86, 'DFC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205452.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205452.png?padding=0.7' where name = 'Antonio Rüdiger' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Trent Alexander-Arnold', 86, 'LD', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231281.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231281.png?padding=0.7' where name = 'Trent Alexander-Arnold' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Daniel Carvajal Ramos', 85, 'LD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p204963.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p204963.png?padding=0.7' where name = 'Daniel Carvajal Ramos' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rodrygo Silva de Goes', 85, 'ED', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243812.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243812.png?padding=0.7' where name = 'Rodrygo Silva de Goes' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Aurélien Tchouaméni', 84, 'MCD', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241637.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241637.png?padding=0.7' where name = 'Aurélien Tchouaméni' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Éder Gabriel Militão', 84, 'DFC', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240130.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240130.png?padding=0.7' where name = 'Éder Gabriel Militão' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Eduardo Camavinga', 83, 'MC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p248243.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p248243.png?padding=0.7' where name = 'Eduardo Camavinga' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('David Alaba', 82, 'DFC', 'Austria', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p197445.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p197445.png?padding=0.7' where name = 'David Alaba' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Dean Huijsen', 82, 'DFC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278349.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278349.png?padding=0.7' where name = 'Dean Huijsen' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Brahim Díaz', 82, 'MD', 'Marruecos', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231410.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231410.png?padding=0.7' where name = 'Brahim Díaz' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ferland Mendy', 81, 'LI', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p228618.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p228618.png?padding=0.7' where name = 'Ferland Mendy' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Andriy Lunin', 81, 'POR', 'Ucrania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243952.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243952.png?padding=0.7' where name = 'Andriy Lunin' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Daniel Ceballos Fernández', 81, 'MC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p222509.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p222509.png?padding=0.7' where name = 'Daniel Ceballos Fernández' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Arda Güler', 81, 'MD', 'Turquía', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264309.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264309.png?padding=0.7' where name = 'Arda Güler' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Álvaro Fernández Carreras', 80, 'LI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268889.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268889.png?padding=0.7' where name = 'Álvaro Fernández Carreras' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Francisco José García Torres', 79, 'LI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246606.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246606.png?padding=0.7' where name = 'Francisco José García Torres' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Franco Mastantuono', 77, 'MCO', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p279173.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p279173.png?padding=0.7' where name = 'Franco Mastantuono' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Endrick Felipe Moreira de Sousa', 77, 'DC', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272505.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272505.png?padding=0.7' where name = 'Endrick Felipe Moreira de Sousa' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Raúl Asencio del Rosario', 77, 'DFC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p75605.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p75605.png?padding=0.7' where name = 'Raúl Asencio del Rosario' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Gonzalo García Torres', 69, 'DC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278399.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278399.png?padding=0.7' where name = 'Gonzalo García Torres' and ovr = 69 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Francisco Javie González Pérez', 63, 'POR', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278394.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278394.png?padding=0.7' where name = 'Francisco Javie González Pérez' and ovr = 63 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Bruno Miguel Borges Fernandes', 87, 'MCO', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212198.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212198.png?padding=0.7' where name = 'Bruno Miguel Borges Fernandes' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Bryan Mbeumo', 85, 'ED', 'Camerún', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243014.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243014.png?padding=0.7' where name = 'Bryan Mbeumo' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Matheus Santos Carneiro da Cunha', 83, 'MCO', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240243.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240243.png?padding=0.7' where name = 'Matheus Santos Carneiro da Cunha' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Matthijs de Ligt', 82, 'DFC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235243.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235243.png?padding=0.7' where name = 'Matthijs de Ligt' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Lisandro Martínez', 81, 'DFC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239301.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239301.png?padding=0.7' where name = 'Lisandro Martínez' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('André Onana', 80, 'POR', 'Camerún', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p226753.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p226753.png?padding=0.7' where name = 'André Onana' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Noussair Mazraoui', 80, 'LD', 'Marruecos', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236401.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236401.png?padding=0.7' where name = 'Noussair Mazraoui' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Benjamin Šeško', 80, 'DC', 'Eslovenia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p260592.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p260592.png?padding=0.7' where name = 'Benjamin Šeško' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Carlos Henrique Venancio Casimiro', 80, 'MCD', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p200145.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p200145.png?padding=0.7' where name = 'Carlos Henrique Venancio Casimiro' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Harry Maguire', 80, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p203263.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p203263.png?padding=0.7' where name = 'Harry Maguire' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('José Diogo Dalot Teixeira', 79, 'LD', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234574.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234574.png?padding=0.7' where name = 'José Diogo Dalot Teixeira' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Luke Shaw', 79, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205988.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205988.png?padding=0.7' where name = 'Luke Shaw' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Manuel Ugarte', 79, 'MCD', 'Uruguay', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253306.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253306.png?padding=0.7' where name = 'Manuel Ugarte' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Amad Diallo', 79, 'MCO', 'Costa de Marfil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254088.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254088.png?padding=0.7' where name = 'Amad Diallo' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Senne Lammens', 78, 'POR', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254803.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254803.png?padding=0.7' where name = 'Senne Lammens' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Leny Yoro', 78, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p269087.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p269087.png?padding=0.7' where name = 'Leny Yoro' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kobbie Mainoo', 77, 'MC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p269136.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p269136.png?padding=0.7' where name = 'Kobbie Mainoo' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mason Mount', 77, 'MCO', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233064.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233064.png?padding=0.7' where name = 'Mason Mount' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Joshua Zirkzee', 77, 'DC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p250961.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p250961.png?padding=0.7' where name = 'Joshua Zirkzee' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Tyrell Malacia', 75, 'LI', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p238041.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p238041.png?padding=0.7' where name = 'Tyrell Malacia' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Altay Bayındır', 75, 'POR', 'Turquía', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243647.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243647.png?padding=0.7' where name = 'Altay Bayındır' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Patrick Dorgu', 74, 'LI', 'Dinamarca', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277432.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277432.png?padding=0.7' where name = 'Patrick Dorgu' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ayden Heaven', 69, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p75087.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p75087.png?padding=0.7' where name = 'Ayden Heaven' and ovr = 69 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Tom Heaton', 67, 'POR', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p163264.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p163264.png?padding=0.7' where name = 'Tom Heaton' and ovr = 67 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Chido Obi', 65, 'DC', 'Dinamarca', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p77354.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p77354.png?padding=0.7' where name = 'Chido Obi' and ovr = 65 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Tyler Fredricson', 65, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p269233.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p269233.png?padding=0.7' where name = 'Tyler Fredricson' and ovr = 65 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Diego León', 64, 'LI', 'Paraguay', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74142.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74142.png?padding=0.7' where name = 'Diego León' and ovr = 64 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rodrigo Hernández Cascante', 90, 'MCD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231866.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231866.png?padding=0.7' where name = 'Rodrigo Hernández Cascante' and ovr = 90 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Erling Haaland', 90, 'DC', 'Noruega', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239085.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239085.png?padding=0.7' where name = 'Erling Haaland' and ovr = 90 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Gianluigi Donnarumma', 89, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p230621.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p230621.png?padding=0.7' where name = 'Gianluigi Donnarumma' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rúben Santos Gato Alves Dias', 86, 'DFC', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239818.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239818.png?padding=0.7' where name = 'Rúben Santos Gato Alves Dias' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Tijjani Reijnders', 86, 'MC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240638.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240638.png?padding=0.7' where name = 'Tijjani Reijnders' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Phil Foden', 85, 'ED', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237692.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237692.png?padding=0.7' where name = 'Phil Foden' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Joško Gvardiol', 84, 'LI', 'Croacia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251517.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251517.png?padding=0.7' where name = 'Joško Gvardiol' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Bernardo Mota Carvalho e Silva', 84, 'MC', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p218667.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p218667.png?padding=0.7' where name = 'Bernardo Mota Carvalho e Silva' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Omar Marmoush', 84, 'DC', 'Egipto', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256675.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256675.png?padding=0.7' where name = 'Omar Marmoush' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mateo Kovačić', 83, 'MC', 'Croacia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p207410.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p207410.png?padding=0.7' where name = 'Mateo Kovačić' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nathan Aké', 83, 'DFC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p208920.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p208920.png?padding=0.7' where name = 'Nathan Aké' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('John Stones', 82, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p203574.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p203574.png?padding=0.7' where name = 'John Stones' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Sávio Moreira de Oliveira', 82, 'ED', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p270409.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p270409.png?padding=0.7' where name = 'Sávio Moreira de Oliveira' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rayan Aït-Nouri', 81, 'LI', 'Argelia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p242641.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p242641.png?padding=0.7' where name = 'Rayan Aït-Nouri' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rayan Cherki', 81, 'ED', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251570.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251570.png?padding=0.7' where name = 'Rayan Cherki' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jérémy Doku', 80, 'EI', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246420.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246420.png?padding=0.7' where name = 'Jérémy Doku' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Matheus Luiz Nunes', 79, 'LD', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253124.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253124.png?padding=0.7' where name = 'Matheus Luiz Nunes' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Stefan Ortega', 79, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p200159.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p200159.png?padding=0.7' where name = 'Stefan Ortega' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nicolás González Iglesias', 79, 'MCD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p255069.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p255069.png?padding=0.7' where name = 'Nicolás González Iglesias' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rico Lewis', 77, 'LD', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p271574.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p271574.png?padding=0.7' where name = 'Rico Lewis' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Abdukodir Khusanov', 77, 'DFC', 'Uzbekistán', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277031.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277031.png?padding=0.7' where name = 'Abdukodir Khusanov' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('James Trafford', 76, 'POR', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p263063.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p263063.png?padding=0.7' where name = 'James Trafford' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kalvin Phillips', 74, 'MCD', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p224081.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p224081.png?padding=0.7' where name = 'Kalvin Phillips' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nico O''Reilly', 73, 'LI', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277427.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277427.png?padding=0.7' where name = 'Nico O''Reilly' and ovr = 73 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Oscar Bobb', 72, 'ED', 'Noruega', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277295.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277295.png?padding=0.7' where name = 'Oscar Bobb' and ovr = 72 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marcus Bettinelli', 70, 'POR', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p204246.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p204246.png?padding=0.7' where name = 'Marcus Bettinelli' and ovr = 70 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Gabriel dos S. Magalhães', 88, 'DFC', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232580.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232580.png?padding=0.7' where name = 'Gabriel dos S. Magalhães' and ovr = 88 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Bukayo Saka', 88, 'ED', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246669.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246669.png?padding=0.7' where name = 'Bukayo Saka' and ovr = 88 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Declan Rice', 87, 'MCD', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234378.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234378.png?padding=0.7' where name = 'Declan Rice' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('William Saliba', 87, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243715.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243715.png?padding=0.7' where name = 'William Saliba' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Martin Ødegaard', 87, 'MC', 'Noruega', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p222665.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p222665.png?padding=0.7' where name = 'Martin Ødegaard' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('David Raya Martin', 87, 'POR', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p220901.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p220901.png?padding=0.7' where name = 'David Raya Martin' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Viktor Gyökeres', 87, 'DC', 'Suecia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241651.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241651.png?padding=0.7' where name = 'Viktor Gyökeres' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mikel Merino Zazón', 83, 'MC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225193.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225193.png?padding=0.7' where name = 'Mikel Merino Zazón' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Martín Zubimendi Ibáñez', 83, 'MCD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p248148.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p248148.png?padding=0.7' where name = 'Martín Zubimendi Ibáñez' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Eberechi Eze', 83, 'MCO', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235794.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235794.png?padding=0.7' where name = 'Eberechi Eze' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Piero Hincapié', 83, 'DFC', 'Ecuador', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256197.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256197.png?padding=0.7' where name = 'Piero Hincapié' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Leandro Trossard', 83, 'EI', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p207421.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p207421.png?padding=0.7' where name = 'Leandro Trossard' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Benjamin White', 83, 'LD', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231936.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231936.png?padding=0.7' where name = 'Benjamin White' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jurriën Timber', 82, 'LD', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251805.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251805.png?padding=0.7' where name = 'Jurriën Timber' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kai Havertz', 82, 'DC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235790.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235790.png?padding=0.7' where name = 'Kai Havertz' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Gabriel Teodoro Martinelli Silva', 81, 'EI', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251566.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251566.png?padding=0.7' where name = 'Gabriel Teodoro Martinelli Silva' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Noni Madueke', 80, 'ED', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254796.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254796.png?padding=0.7' where name = 'Noni Madueke' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Gabriel Fernando de Jesus', 80, 'DC', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p230666.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p230666.png?padding=0.7' where name = 'Gabriel Fernando de Jesus' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Christian Nørgaard', 80, 'MCD', 'Dinamarca', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210697.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210697.png?padding=0.7' where name = 'Christian Nørgaard' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kepa Arrizabalaga', 79, 'POR', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p206585.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p206585.png?padding=0.7' where name = 'Kepa Arrizabalaga' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Myles Lewis-Skelly', 78, 'LI', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278773.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278773.png?padding=0.7' where name = 'Myles Lewis-Skelly' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Riccardo Calafiori', 78, 'LI', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257711.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257711.png?padding=0.7' where name = 'Riccardo Calafiori' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Cristhian Mosquera Ibargüen', 77, 'DFC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264846.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264846.png?padding=0.7' where name = 'Cristhian Mosquera Ibargüen' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ethan Nwaneri', 76, 'ED', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p271807.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p271807.png?padding=0.7' where name = 'Ethan Nwaneri' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Xavi Simons', 84, 'MCO', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245367.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245367.png?padding=0.7' where name = 'Xavi Simons' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('James Maddison', 84, 'MC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p220697.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p220697.png?padding=0.7' where name = 'James Maddison' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Dejan Kulusevski', 83, 'MC', 'Suecia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247394.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247394.png?padding=0.7' where name = 'Dejan Kulusevski' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('João Maria Palhinha Gonçalves', 83, 'MCD', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229391.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229391.png?padding=0.7' where name = 'João Maria Palhinha Gonçalves' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pedro Antonio Porro Sauceda', 82, 'LD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243576.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243576.png?padding=0.7' where name = 'Pedro Antonio Porro Sauceda' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Guglielmo Vicario', 82, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240091.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240091.png?padding=0.7' where name = 'Guglielmo Vicario' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Micky van de Ven', 82, 'DFC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264453.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264453.png?padding=0.7' where name = 'Micky van de Ven' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Cristian Romero', 82, 'DFC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232488.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232488.png?padding=0.7' where name = 'Cristian Romero' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Randal Kolo Muani', 81, 'DC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237679.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237679.png?padding=0.7' where name = 'Randal Kolo Muani' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Destiny Udogie', 80, 'LI', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259583.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259583.png?padding=0.7' where name = 'Destiny Udogie' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mohammed Kudus', 80, 'ED', 'Ghana', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245155.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245155.png?padding=0.7' where name = 'Mohammed Kudus' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rodrigo Bentancur', 80, 'MCD', 'Uruguay', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p227535.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p227535.png?padding=0.7' where name = 'Rodrigo Bentancur' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Dominic Solanke', 80, 'DC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225539.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225539.png?padding=0.7' where name = 'Dominic Solanke' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pape Matar Sarr', 79, 'MC', 'Senegal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259868.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259868.png?padding=0.7' where name = 'Pape Matar Sarr' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Brennan Johnson', 79, 'ED', 'Gales', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251421.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251421.png?padding=0.7' where name = 'Brennan Johnson' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kevin Danso', 79, 'DFC', 'Austria', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237985.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237985.png?padding=0.7' where name = 'Kevin Danso' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Yves Bissouma', 78, 'MCD', 'Malí', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236480.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236480.png?padding=0.7' where name = 'Yves Bissouma' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Richarlison de Andrade', 78, 'DC', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231943.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231943.png?padding=0.7' where name = 'Richarlison de Andrade' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Djed Spence', 78, 'LD', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243702.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243702.png?padding=0.7' where name = 'Djed Spence' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Lucas Bergvall', 77, 'MC', 'Suecia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272926.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272926.png?padding=0.7' where name = 'Lucas Bergvall' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mathys Tel', 77, 'DC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268421.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268421.png?padding=0.7' where name = 'Mathys Tel' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Archie Gray', 75, 'MCD', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p270208.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p270208.png?padding=0.7' where name = 'Archie Gray' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Antonín Kinský', 75, 'POR', 'República Checa', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p73580.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p73580.png?padding=0.7' where name = 'Antonín Kinský' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ben Davies', 75, 'DFC', 'Gales', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205923.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205923.png?padding=0.7' where name = 'Ben Davies' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Wilson Odobert', 75, 'EI', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p270579.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p270579.png?padding=0.7' where name = 'Wilson Odobert' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Radu Drăgușin', 75, 'DFC', 'Rumanía', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p260105.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p260105.png?padding=0.7' where name = 'Radu Drăgușin' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kota Takai', 72, 'DFC', 'Japón', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264702.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264702.png?padding=0.7' where name = 'Kota Takai' and ovr = 72 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Brandon Austin', 67, 'POR', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236568.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236568.png?padding=0.7' where name = 'Brandon Austin' and ovr = 67 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Dane Scarlett', 65, 'DC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p261025.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p261025.png?padding=0.7' where name = 'Dane Scarlett' and ovr = 65 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Gleison Bremer Silva Nascimento', 85, 'DFC', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239580.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239580.png?padding=0.7' where name = 'Gleison Bremer Silva Nascimento' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Manuel Locatelli', 84, 'MCD', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p222077.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p222077.png?padding=0.7' where name = 'Manuel Locatelli' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Loïs Openda', 83, 'DC', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243580.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243580.png?padding=0.7' where name = 'Loïs Openda' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jonathan David', 82, 'DC', 'Canadá', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243630.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243630.png?padding=0.7' where name = 'Jonathan David' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Dušan Vlahović', 82, 'DC', 'Serbia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246430.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246430.png?padding=0.7' where name = 'Dušan Vlahović' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Khéphren Thuram', 81, 'MC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247246.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247246.png?padding=0.7' where name = 'Khéphren Thuram' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Filip Kostić', 81, 'MI', 'Serbia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p208574.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p208574.png?padding=0.7' where name = 'Filip Kostić' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Michele Di Gregorio', 81, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235840.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235840.png?padding=0.7' where name = 'Michele Di Gregorio' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Teun Koopmeiners', 81, 'MCO', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240679.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240679.png?padding=0.7' where name = 'Teun Koopmeiners' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pierre Kalulu', 80, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p255654.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p255654.png?padding=0.7' where name = 'Pierre Kalulu' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Federico Gatti', 80, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p266872.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p266872.png?padding=0.7' where name = 'Federico Gatti' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Andrea Cambiaso', 79, 'LI', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p258966.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p258966.png?padding=0.7' where name = 'Andrea Cambiaso' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kenan Yıldız', 79, 'MCO', 'Turquía', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277954.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277954.png?padding=0.7' where name = 'Kenan Yıldız' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Edon Zhegrova', 79, 'MD', 'Kosovo', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239763.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239763.png?padding=0.7' where name = 'Edon Zhegrova' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Francisco F. da Conceição', 79, 'MD', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p261050.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p261050.png?padding=0.7' where name = 'Francisco F. da Conceição' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Arkadiusz Milik', 79, 'DC', 'Polonia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205175.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205175.png?padding=0.7' where name = 'Arkadiusz Milik' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Weston McKennie', 78, 'MC', 'Estados Unidos', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p238744.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p238744.png?padding=0.7' where name = 'Weston McKennie' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mattia Perin', 78, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p198009.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p198009.png?padding=0.7' where name = 'Mattia Perin' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('João Mário Neto Lopes', 77, 'LD', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257290.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257290.png?padding=0.7' where name = 'João Mário Neto Lopes' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Daniele Rugani', 75, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p211320.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p211320.png?padding=0.7' where name = 'Daniele Rugani' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Fabio Miretti', 74, 'MC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268802.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268802.png?padding=0.7' where name = 'Fabio Miretti' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Lloyd Kelly', 74, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231512.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231512.png?padding=0.7' where name = 'Lloyd Kelly' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Juan David Cabal', 74, 'LI', 'Colombia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251870.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251870.png?padding=0.7' where name = 'Juan David Cabal' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Carlo Pinsoglio', 69, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p189342.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p189342.png?padding=0.7' where name = 'Carlo Pinsoglio' and ovr = 69 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jonas Rouhi', 66, 'LI', 'Suecia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74329.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74329.png?padding=0.7' where name = 'Jonas Rouhi' and ovr = 66 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Vasilije Adžić', 62, 'MCO', 'Montenegro', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p75085.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p75085.png?padding=0.7' where name = 'Vasilije Adžić' and ovr = 62 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mike Maignan', 87, 'POR', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p215698.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p215698.png?padding=0.7' where name = 'Mike Maignan' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Christian Pulisic', 84, 'ED', 'Estados Unidos', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p227796.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p227796.png?padding=0.7' where name = 'Christian Pulisic' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rafael da Conceição Leão', 84, 'EI', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241721.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241721.png?padding=0.7' where name = 'Rafael da Conceição Leão' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Adrien Rabiot', 83, 'MCO', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210008.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210008.png?padding=0.7' where name = 'Adrien Rabiot' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Luka Modrić', 83, 'MC', 'Croacia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p177003.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p177003.png?padding=0.7' where name = 'Luka Modrić' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Youssouf Fofana', 81, 'MCD', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245630.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245630.png?padding=0.7' where name = 'Youssouf Fofana' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Christopher Nkunku', 81, 'MCO', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232411.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232411.png?padding=0.7' where name = 'Christopher Nkunku' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Fikayo Tomori', 81, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232756.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p232756.png?padding=0.7' where name = 'Fikayo Tomori' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ruben Loftus-Cheek', 80, 'MC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p213666.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p213666.png?padding=0.7' where name = 'Ruben Loftus-Cheek' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pervis Estupiñán', 79, 'LI', 'Ecuador', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237942.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237942.png?padding=0.7' where name = 'Pervis Estupiñán' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alexis Saelemaekers', 79, 'MD', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p242664.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p242664.png?padding=0.7' where name = 'Alexis Saelemaekers' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Santiago Giménez', 79, 'DC', 'México', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245152.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245152.png?padding=0.7' where name = 'Santiago Giménez' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Yacine Adli', 78, 'MCD', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243627.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243627.png?padding=0.7' where name = 'Yacine Adli' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Samuele Ricci', 78, 'MCD', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253473.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253473.png?padding=0.7' where name = 'Samuele Ricci' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pietro Terracciano', 78, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205812.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p205812.png?padding=0.7' where name = 'Pietro Terracciano' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Matteo Gabbia', 78, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240277.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240277.png?padding=0.7' where name = 'Matteo Gabbia' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ardon Jashari', 77, 'MCD', 'Suiza', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257186.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257186.png?padding=0.7' where name = 'Ardon Jashari' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Strahinja Pavlović', 76, 'DFC', 'Serbia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254840.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254840.png?padding=0.7' where name = 'Strahinja Pavlović' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Koni De Winter', 74, 'DFC', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p265774.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p265774.png?padding=0.7' where name = 'Koni De Winter' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Zachary Athekame', 65, 'LD', 'Suiza', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p279782.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p279782.png?padding=0.7' where name = 'Zachary Athekame' and ovr = 65 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('David Odogu', 65, 'DFC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p73286.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p73286.png?padding=0.7' where name = 'David Odogu' and ovr = 65 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Davide Bartesaghi', 62, 'LI', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278237.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278237.png?padding=0.7' where name = 'Davide Bartesaghi' and ovr = 62 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Lorenzo Torriani', 61, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p72179.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p72179.png?padding=0.7' where name = 'Lorenzo Torriani' and ovr = 61 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Lautaro Martínez', 88, 'DC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231478.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231478.png?padding=0.7' where name = 'Lautaro Martínez' and ovr = 88 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alessandro Bastoni', 87, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237383.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237383.png?padding=0.7' where name = 'Alessandro Bastoni' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Yann Sommer', 87, 'POR', 'Suiza', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p177683.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p177683.png?padding=0.7' where name = 'Yann Sommer' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nicolò Barella', 87, 'MC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p224232.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p224232.png?padding=0.7' where name = 'Nicolò Barella' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Hakan Çalhanoğlu', 86, 'MCD', 'Turquía', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p208128.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p208128.png?padding=0.7' where name = 'Hakan Çalhanoğlu' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Federico Dimarco', 85, 'LI', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p226268.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p226268.png?padding=0.7' where name = 'Federico Dimarco' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marcus Thuram', 85, 'DC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p228093.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p228093.png?padding=0.7' where name = 'Marcus Thuram' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Denzel Dumfries', 84, 'LD', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233096.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233096.png?padding=0.7' where name = 'Denzel Dumfries' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Francesco Acerbi', 84, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p199845.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p199845.png?padding=0.7' where name = 'Francesco Acerbi' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Stefan de Vrij', 84, 'DFC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p198176.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p198176.png?padding=0.7' where name = 'Stefan de Vrij' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Henrikh Mkhitaryan', 83, 'MC', 'Armenia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192883.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192883.png?padding=0.7' where name = 'Henrikh Mkhitaryan' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Manuel Akanji', 82, 'DFC', 'Suiza', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229237.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229237.png?padding=0.7' where name = 'Manuel Akanji' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Davide Frattesi', 81, 'MC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239807.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239807.png?padding=0.7' where name = 'Davide Frattesi' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Carlos Augusto Zopolato Neves', 81, 'LI', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p258648.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p258648.png?padding=0.7' where name = 'Carlos Augusto Zopolato Neves' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Matteo Darmian', 81, 'LD', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p184392.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p184392.png?padding=0.7' where name = 'Matteo Darmian' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Piotr Zieliński', 80, 'MC', 'Polonia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210406.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210406.png?padding=0.7' where name = 'Piotr Zieliński' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Luis Henrique Tomaz de Lima', 78, 'MD', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256632.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256632.png?padding=0.7' where name = 'Luis Henrique Tomaz de Lima' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Yann Aurel Bisseck', 76, 'DFC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241736.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241736.png?padding=0.7' where name = 'Yann Aurel Bisseck' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Yoan Bonny', 76, 'DC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259565.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259565.png?padding=0.7' where name = 'Yoan Bonny' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Andy Diouf', 75, 'MC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268534.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268534.png?padding=0.7' where name = 'Andy Diouf' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Josep Martínez Riera', 75, 'POR', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243311.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243311.png?padding=0.7' where name = 'Josep Martínez Riera' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Petar Sučić', 74, 'MC', 'Croacia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p276278.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p276278.png?padding=0.7' where name = 'Petar Sučić' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Francesco Pio Esposito', 71, 'DC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277327.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p277327.png?padding=0.7' where name = 'Francesco Pio Esposito' and ovr = 71 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Raffaele Di Gennaro', 68, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p219715.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p219715.png?padding=0.7' where name = 'Raffaele Di Gennaro' and ovr = 68 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Tomás Palacios', 67, 'DFC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268558.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268558.png?padding=0.7' where name = 'Tomás Palacios' and ovr = 67 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Kevin De Bruyne', 87, 'MC', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192985.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192985.png?padding=0.7' where name = 'Kevin De Bruyne' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Scott McTominay', 85, 'MC', 'Escocia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237238.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237238.png?padding=0.7' where name = 'Scott McTominay' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Romelu Lukaku', 84, 'DC', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192505.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p192505.png?padding=0.7' where name = 'Romelu Lukaku' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Giovanni Di Lorenzo', 83, 'LD', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p217870.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p217870.png?padding=0.7' where name = 'Giovanni Di Lorenzo' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Stanislav Lobotka', 83, 'MC', 'Eslovaquia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216435.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216435.png?padding=0.7' where name = 'Stanislav Lobotka' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Amir Rrahmani', 83, 'DFC', 'Kosovo', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p244263.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p244263.png?padding=0.7' where name = 'Amir Rrahmani' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('André-Franck Zambo Anguissa', 82, 'MC', 'Camerún', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p227236.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p227236.png?padding=0.7' where name = 'André-Franck Zambo Anguissa' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alex Meret', 82, 'POR', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225116.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225116.png?padding=0.7' where name = 'Alex Meret' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alessandro Buongiorno', 82, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243241.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p243241.png?padding=0.7' where name = 'Alessandro Buongiorno' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Miguel Gutiérrez Ortega', 81, 'LI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p261865.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p261865.png?padding=0.7' where name = 'Miguel Gutiérrez Ortega' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Matteo Politano', 81, 'ED', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216409.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216409.png?padding=0.7' where name = 'Matteo Politano' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('David Neres Campos', 81, 'EI', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236632.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236632.png?padding=0.7' where name = 'David Neres Campos' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Noa Lang', 80, 'EI', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239380.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239380.png?padding=0.7' where name = 'Noa Lang' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Vanja Milinković-Savić', 79, 'POR', 'Serbia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p224836.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p224836.png?padding=0.7' where name = 'Vanja Milinković-Savić' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Leonardo Spinazzola', 78, 'LI', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p202884.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p202884.png?padding=0.7' where name = 'Leonardo Spinazzola' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mathías Olivera', 78, 'LI', 'Uruguay', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240716.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240716.png?padding=0.7' where name = 'Mathías Olivera' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Sam Beukema', 78, 'DFC', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p262394.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p262394.png?padding=0.7' where name = 'Sam Beukema' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Eljif Elmas', 77, 'MI', 'Macedonia del Norte', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241390.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241390.png?padding=0.7' where name = 'Eljif Elmas' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Rasmus Højlund', 76, 'DC', 'Dinamarca', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259399.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259399.png?padding=0.7' where name = 'Rasmus Højlund' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Lorenzo Lucca', 76, 'DC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268474.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268474.png?padding=0.7' where name = 'Lorenzo Lucca' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Billy Gilmour', 74, 'MC', 'Escocia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245992.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245992.png?padding=0.7' where name = 'Billy Gilmour' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Juan Guilherme Nunes Jesus', 74, 'DFC', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p200752.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p200752.png?padding=0.7' where name = 'Juan Guilherme Nunes Jesus' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pasquale Mazzocchi', 72, 'LD', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239679.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p239679.png?padding=0.7' where name = 'Pasquale Mazzocchi' and ovr = 72 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Luca Marianucci', 68, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278319.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278319.png?padding=0.7' where name = 'Luca Marianucci' and ovr = 68 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nikita Contini', 67, 'POR', 'Ucrania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p220532.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p220532.png?padding=0.7' where name = 'Nikita Contini' and ovr = 67 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Giuseppe Ambrosino', 67, 'DC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272726.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272726.png?padding=0.7' where name = 'Giuseppe Ambrosino' and ovr = 67 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Antonio Vergara', 65, 'ED', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p276706.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p276706.png?padding=0.7' where name = 'Antonio Vergara' and ovr = 65 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Coli Saco', 61, 'MC', 'Malí', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74496.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p74496.png?padding=0.7' where name = 'Coli Saco' and ovr = 61 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Joshua Kimmich', 89, 'MCD', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212622.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212622.png?padding=0.7' where name = 'Joshua Kimmich' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Harry Kane', 89, 'DC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p202126.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p202126.png?padding=0.7' where name = 'Harry Kane' and ovr = 89 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jamal Musiala', 88, 'MCO', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256790.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256790.png?padding=0.7' where name = 'Jamal Musiala' and ovr = 88 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jonathan Tah', 87, 'DFC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p213331.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p213331.png?padding=0.7' where name = 'Jonathan Tah' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Michael Olise', 86, 'MD', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247827.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247827.png?padding=0.7' where name = 'Michael Olise' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Luis Díaz', 85, 'MI', 'Colombia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241084.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241084.png?padding=0.7' where name = 'Luis Díaz' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Dayot Upamecano', 85, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229558.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229558.png?padding=0.7' where name = 'Dayot Upamecano' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alphonso Davies', 84, 'LI', 'Canadá', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234396.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234396.png?padding=0.7' where name = 'Alphonso Davies' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Manuel Neuer', 84, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p167495.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p167495.png?padding=0.7' where name = 'Manuel Neuer' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Leon Goretzka', 82, 'MC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p209658.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p209658.png?padding=0.7' where name = 'Leon Goretzka' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Konrad Laimer', 82, 'LD', 'Austria', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225375.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p225375.png?padding=0.7' where name = 'Konrad Laimer' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Serge Gnabry', 82, 'MI', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p206113.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p206113.png?padding=0.7' where name = 'Serge Gnabry' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Min Jae Kim', 82, 'DFC', 'República de Corea', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237086.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237086.png?padding=0.7' where name = 'Min Jae Kim' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Raphaël Guerreiro', 80, 'LI', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p209889.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p209889.png?padding=0.7' where name = 'Raphaël Guerreiro' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nicolas Jackson', 80, 'DC', 'Senegal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259197.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259197.png?padding=0.7' where name = 'Nicolas Jackson' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Aleksandar Pavlović', 79, 'MCD', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p275298.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p275298.png?padding=0.7' where name = 'Aleksandar Pavlović' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Hiroki Ito', 78, 'DFC', 'Japón', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234205.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234205.png?padding=0.7' where name = 'Hiroki Ito' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Josip Stanišić', 78, 'DFC', 'Croacia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p250955.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p250955.png?padding=0.7' where name = 'Josip Stanišić' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Sacha Boey', 77, 'LD', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p248266.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p248266.png?padding=0.7' where name = 'Sacha Boey' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Tom Bischof', 76, 'MC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p263765.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p263765.png?padding=0.7' where name = 'Tom Bischof' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jonas Urbig', 74, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p263887.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p263887.png?padding=0.7' where name = 'Jonas Urbig' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Sven Ulreich', 73, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p186569.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p186569.png?padding=0.7' where name = 'Sven Ulreich' and ovr = 73 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Lennart Karl', 63, 'MCO', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p78063.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p78063.png?padding=0.7' where name = 'Lennart Karl' and ovr = 63 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('David Santos Daiber', 59, 'MCD', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p79317.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p79317.png?padding=0.7' where name = 'David Santos Daiber' and ovr = 59 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Leon Klanac', 56, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p76337.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p76337.png?padding=0.7' where name = 'Leon Klanac' and ovr = 56 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Patrik Schick', 85, 'DC', 'República Checa', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234236.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p234236.png?padding=0.7' where name = 'Patrik Schick' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alejandro Grimaldo García', 84, 'MI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210035.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210035.png?padding=0.7' where name = 'Alejandro Grimaldo García' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Exequiel Palacios', 84, 'MC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231521.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231521.png?padding=0.7' where name = 'Exequiel Palacios' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Aleix García Serrano', 83, 'MC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p228813.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p228813.png?padding=0.7' where name = 'Aleix García Serrano' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Malik Tillman', 82, 'MCO', 'Estados Unidos', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256853.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p256853.png?padding=0.7' where name = 'Malik Tillman' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Robert Andrich', 81, 'MCD', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212242.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212242.png?padding=0.7' where name = 'Robert Andrich' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Edmond Tapsoba', 81, 'DFC', 'Burkina Faso', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247263.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247263.png?padding=0.7' where name = 'Edmond Tapsoba' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Martin Terrier', 79, 'DC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236786.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p236786.png?padding=0.7' where name = 'Martin Terrier' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jonas Hofmann', 78, 'MCO', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210324.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210324.png?padding=0.7' where name = 'Jonas Hofmann' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Mark Flekken', 78, 'POR', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p211738.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p211738.png?padding=0.7' where name = 'Mark Flekken' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nathan Tella', 78, 'MD', 'Nigeria', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237328.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p237328.png?padding=0.7' where name = 'Nathan Tella' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Loïc Badé', 78, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p255106.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p255106.png?padding=0.7' where name = 'Loïc Badé' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Eliesse Ben Seghir', 76, 'MI', 'Marruecos', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272781.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272781.png?padding=0.7' where name = 'Eliesse Ben Seghir' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ezequiel Fernández', 75, 'MCD', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p262151.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p262151.png?padding=0.7' where name = 'Ezequiel Fernández' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jarell Quansah', 75, 'DFC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p273651.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p273651.png?padding=0.7' where name = 'Jarell Quansah' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Claudio Echeverri', 74, 'MCO', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p276528.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p276528.png?padding=0.7' where name = 'Claudio Echeverri' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Janis Blaswich', 73, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p204092.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p204092.png?padding=0.7' where name = 'Janis Blaswich' and ovr = 73 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ibrahim Maza', 71, 'MCO', 'Argelia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p275029.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p275029.png?padding=0.7' where name = 'Ibrahim Maza' and ovr = 71 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Arthur Augusto de Matos Soares', 71, 'LD', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p275028.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p275028.png?padding=0.7' where name = 'Arthur Augusto de Matos Soares' and ovr = 71 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ernest Poku', 70, 'MD', 'Holanda', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264219.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p264219.png?padding=0.7' where name = 'Ernest Poku' and ovr = 70 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jeanuël Belocian', 70, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268622.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p268622.png?padding=0.7' where name = 'Jeanuël Belocian' and ovr = 70 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Christian Kofane', 68, 'DC', 'Camerún', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p76416.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p76416.png?padding=0.7' where name = 'Christian Kofane' and ovr = 68 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Niklas Lomb', 66, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210366.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210366.png?padding=0.7' where name = 'Niklas Lomb' and ovr = 66 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Axel Tape', 65, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p75736.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p75736.png?padding=0.7' where name = 'Axel Tape' and ovr = 65 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alejo Sarco', 64, 'DC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p71101.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p71101.png?padding=0.7' where name = 'Alejo Sarco' and ovr = 64 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jeremiah Mensah', 61, 'MC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p80665.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p80665.png?padding=0.7' where name = 'Jeremiah Mensah' and ovr = 61 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Serhou Guirassy', 87, 'DC', 'Guinea', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p215441.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p215441.png?padding=0.7' where name = 'Serhou Guirassy' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Gregor Kobel', 86, 'POR', 'Suiza', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235073.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235073.png?padding=0.7' where name = 'Gregor Kobel' and ovr = 86 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nico Schlotterbeck', 85, 'DFC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247819.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247819.png?padding=0.7' where name = 'Nico Schlotterbeck' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Julian Brandt', 83, 'MCO', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212194.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212194.png?padding=0.7' where name = 'Julian Brandt' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Felix Nmecha', 82, 'MCD', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246863.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246863.png?padding=0.7' where name = 'Felix Nmecha' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Emre Can', 82, 'DFC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p208333.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p208333.png?padding=0.7' where name = 'Emre Can' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Waldemar Anton', 82, 'DFC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229476.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229476.png?padding=0.7' where name = 'Waldemar Anton' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Karim Adeyemi', 81, 'MD', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251852.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p251852.png?padding=0.7' where name = 'Karim Adeyemi' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Niklas Süle', 81, 'DFC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212190.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p212190.png?padding=0.7' where name = 'Niklas Süle' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marcel Sabitzer', 80, 'MCD', 'Austria', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p204923.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p204923.png?padding=0.7' where name = 'Marcel Sabitzer' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pascal Groß', 80, 'MCD', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p190765.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p190765.png?padding=0.7' where name = 'Pascal Groß' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Ramy Bensebaini', 79, 'LI', 'Argelia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p224196.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p224196.png?padding=0.7' where name = 'Ramy Bensebaini' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Julian Ryerson', 79, 'LD', 'Noruega', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229891.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p229891.png?padding=0.7' where name = 'Julian Ryerson' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Maximilian Beier', 79, 'DC', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254117.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p254117.png?padding=0.7' where name = 'Maximilian Beier' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Fábio Daniel Soares Silva', 79, 'DC', 'Portugal', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p252037.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p252037.png?padding=0.7' where name = 'Fábio Daniel Soares Silva' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Daniel Svensson', 77, 'LI', 'Suecia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259716.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259716.png?padding=0.7' where name = 'Daniel Svensson' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Yan Bueno Couto', 77, 'LD', 'Brasil', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259075.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259075.png?padding=0.7' where name = 'Yan Bueno Couto' and ovr = 77 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Carney Chukwuemeka', 76, 'MCO', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259356.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259356.png?padding=0.7' where name = 'Carney Chukwuemeka' and ovr = 76 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Salih Özcan', 75, 'MCD', 'Turquía', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235407.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p235407.png?padding=0.7' where name = 'Salih Özcan' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alexander Meyer', 75, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241050.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p241050.png?padding=0.7' where name = 'Alexander Meyer' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jobe Bellingham', 74, 'MC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p270964.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p270964.png?padding=0.7' where name = 'Jobe Bellingham' and ovr = 74 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Julien Duranville', 72, 'MD', 'Bélgica', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p262105.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p262105.png?padding=0.7' where name = 'Julien Duranville' and ovr = 72 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Patrick Drewes', 71, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210772.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p210772.png?padding=0.7' where name = 'Patrick Drewes' and ovr = 71 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Aaron Anselmino', 70, 'DFC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278455.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278455.png?padding=0.7' where name = 'Aaron Anselmino' and ovr = 70 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Cole Campbell', 67, 'MD', 'Estados Unidos', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p73057.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p73057.png?padding=0.7' where name = 'Cole Campbell' and ovr = 67 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Almugera Kabar', 64, 'LI', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278854.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p278854.png?padding=0.7' where name = 'Almugera Kabar' and ovr = 64 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Silas Ostrzinski', 63, 'POR', 'Alemania', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p266906.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p266906.png?padding=0.7' where name = 'Silas Ostrzinski' and ovr = 63 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Filippo Mane', 62, 'DFC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p73016.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p73016.png?padding=0.7' where name = 'Filippo Mane' and ovr = 62 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jan Oblak', 88, 'POR', 'Eslovenia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p200389.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p200389.png?padding=0.7' where name = 'Jan Oblak' and ovr = 88 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Julián Alvarez', 87, 'DC', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246191.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p246191.png?padding=0.7' where name = 'Julián Alvarez' and ovr = 87 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Antoine Griezmann', 85, 'DC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p194765.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p194765.png?padding=0.7' where name = 'Antoine Griezmann' and ovr = 85 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marcos Llorente Moreno', 84, 'LD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p226161.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p226161.png?padding=0.7' where name = 'Marcos Llorente Moreno' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alejandro Baena Rodríguez', 84, 'MI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257279.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p257279.png?padding=0.7' where name = 'Alejandro Baena Rodríguez' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Alexander Sørloth', 84, 'DC', 'Noruega', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216549.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216549.png?padding=0.7' where name = 'Alexander Sørloth' and ovr = 84 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Dávid Hancko', 83, 'DFC', 'Eslovaquia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247103.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p247103.png?padding=0.7' where name = 'Dávid Hancko' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('José María Giménez', 83, 'DFC', 'Uruguay', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216460.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p216460.png?padding=0.7' where name = 'José María Giménez' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Robin Le Normand', 83, 'DFC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233486.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233486.png?padding=0.7' where name = 'Robin Le Normand' and ovr = 83 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Pablo Barrios Rivas', 82, 'MC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272449.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p272449.png?padding=0.7' where name = 'Pablo Barrios Rivas' and ovr = 82 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Conor Gallagher', 81, 'MC', 'Inglaterra', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p238216.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p238216.png?padding=0.7' where name = 'Conor Gallagher' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('João Lucas de Souza Cardoso', 81, 'MCD', 'Estados Unidos', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259516.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259516.png?padding=0.7' where name = 'João Lucas de Souza Cardoso' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Jorge Resurrección', 81, 'MC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p193747.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p193747.png?padding=0.7' where name = 'Jorge Resurrección' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Giuliano Simeone', 81, 'MD', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253396.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253396.png?padding=0.7' where name = 'Giuliano Simeone' and ovr = 81 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Javier Galán Gil', 80, 'LI', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231591.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p231591.png?padding=0.7' where name = 'Javier Galán Gil' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Clément Lenglet', 80, 'DFC', 'Francia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p220440.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p220440.png?padding=0.7' where name = 'Clément Lenglet' and ovr = 80 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nahuel Molina', 79, 'LD', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233084.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p233084.png?padding=0.7' where name = 'Nahuel Molina' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Juan Musso', 79, 'POR', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p214979.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p214979.png?padding=0.7' where name = 'Juan Musso' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Thiago Almada', 79, 'MCO', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245371.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p245371.png?padding=0.7' where name = 'Thiago Almada' and ovr = 79 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Nico Gonzalez', 78, 'MD', 'Argentina', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240690.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p240690.png?padding=0.7' where name = 'Nico Gonzalez' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Giacomo Raspadori', 78, 'DC', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253002.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p253002.png?padding=0.7' where name = 'Giacomo Raspadori' and ovr = 78 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Matteo Ruggeri', 75, 'MI', 'Italia', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259584.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p259584.png?padding=0.7' where name = 'Matteo Ruggeri' and ovr = 75 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Marc Pubill Pagès', 73, 'LD', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p266039.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p266039.png?padding=0.7' where name = 'Marc Pubill Pagès' and ovr = 73 and headshot_url is null;
insert into players (name, ovr, position, country_name, headshot_url, card_image_url, price, clause) values ('Carlos Martín Domínguez', 70, 'DC', 'España', 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p265396.png?padding=0.7', null, 0, 0) on conflict do nothing;
update players set headshot_url = 'https://ratings-images-prod.pulse.ea.com/FC25/full/player-portraits/p265396.png?padding=0.7' where name = 'Carlos Martín Domínguez' and ovr = 70 and headshot_url is null;

-- Team rosters (team_players)
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mohamed Salah' and p.ovr = 91 and p.position = 'MD' and p.country_name = 'Egipto'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Virgil van Dijk' and p.ovr = 90 and p.position = 'DFC' and p.country_name = 'Holanda'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alisson Ramses Becker' and p.ovr = 89 and p.position = 'POR' and p.country_name = 'Brasil'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Florian Wirtz' and p.ovr = 89 and p.position = 'MCO' and p.country_name = 'Alemania'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alexander Isak' and p.ovr = 88 and p.position = 'DC' and p.country_name = 'Suecia'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alexis Mac Allister' and p.ovr = 87 and p.position = 'MC' and p.country_name = 'Argentina'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ibrahima Konaté' and p.ovr = 86 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ryan Gravenberch' and p.ovr = 85 and p.position = 'MCD' and p.country_name = 'Holanda'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Giorgi Mamardashvili' and p.ovr = 84 and p.position = 'POR' and p.country_name = 'Georgia'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Cody Gakpo' and p.ovr = 84 and p.position = 'MI' and p.country_name = 'Holanda'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Dominik Szoboszlai' and p.ovr = 83 and p.position = 'MCO' and p.country_name = 'Hungría'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jeremie Frimpong' and p.ovr = 83 and p.position = 'LD' and p.country_name = 'Holanda'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Hugo Ekitiké' and p.ovr = 83 and p.position = 'DC' and p.country_name = 'Francia'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Milos Kerkez' and p.ovr = 82 and p.position = 'LI' and p.country_name = 'Hungría'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Andrew Robertson' and p.ovr = 82 and p.position = 'LI' and p.country_name = 'Escocia'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Federico Chiesa' and p.ovr = 81 and p.position = 'MD' and p.country_name = 'Italia'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Curtis Jones' and p.ovr = 80 and p.position = 'MCO' and p.country_name = 'Inglaterra'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Wataru Endo' and p.ovr = 79 and p.position = 'MCD' and p.country_name = 'Japón'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Joe Gomez' and p.ovr = 79 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Conor Bradley' and p.ovr = 78 and p.position = 'LD' and p.country_name = 'Irlanda del N.'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Stefan Bajcetic Maquieira' and p.ovr = 73 and p.position = 'MCD' and p.country_name = 'España'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Freddie Woodman' and p.ovr = 71 and p.position = 'POR' and p.country_name = 'Inglaterra'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Giovanni Leoni' and p.ovr = 69 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rio Ngumoha' and p.ovr = 68 and p.position = 'MI' and p.country_name = 'Inglaterra'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Calvin Ramsay' and p.ovr = 65 and p.position = 'LD' and p.country_name = 'Escocia'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ármin Pécsi' and p.ovr = 64 and p.position = 'POR' and p.country_name = 'Hungría'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Trey Nyoni' and p.ovr = 64 and p.position = 'MC' and p.country_name = 'Inglaterra'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rhys Williams' and p.ovr = 61 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Liverpool'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Raphael Dias Belloli' and p.ovr = 89 and p.position = 'MI' and p.country_name = 'Brasil'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Lamine Yamal Nasraoui Ebana' and p.ovr = 89 and p.position = 'MD' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pedro González López' and p.ovr = 89 and p.position = 'MC' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Robert Lewandowski' and p.ovr = 88 and p.position = 'DC' and p.country_name = 'Polonia'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Frenkie de Jong' and p.ovr = 87 and p.position = 'MC' and p.country_name = 'Holanda'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jules Koundé' and p.ovr = 87 and p.position = 'LD' and p.country_name = 'Francia'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marc-André ter Stegen' and p.ovr = 86 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Daniel Olmo Carvajal' and p.ovr = 85 and p.position = 'MCO' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Wojciech Szczęsny' and p.ovr = 84 and p.position = 'POR' and p.country_name = 'Polonia'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Joan García Pons' and p.ovr = 83 and p.position = 'POR' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pablo Martín Páez Gavira' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alejandro Balde Martínez' and p.ovr = 83 and p.position = 'LI' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ferran Torres García' and p.ovr = 83 and p.position = 'EI' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ronald Araujo' and p.ovr = 83 and p.position = 'DFC' and p.country_name = 'Uruguay'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pau Cubarsí Paredes' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Fermín López Marín' and p.ovr = 80 and p.position = 'MCO' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marcus Rashford' and p.ovr = 80 and p.position = 'MI' and p.country_name = 'Inglaterra'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Andreas Christensen' and p.ovr = 80 and p.position = 'DFC' and p.country_name = 'Dinamarca'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marc Casadó Torras' and p.ovr = 79 and p.position = 'MCD' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Eric García Martret' and p.ovr = 79 and p.position = 'DFC' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Gerard Martín Langreo' and p.ovr = 74 and p.position = 'LI' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marc Bernal Casas' and p.ovr = 73 and p.position = 'MCD' and p.country_name = 'España'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Roony Bardghji' and p.ovr = 69 and p.position = 'MD' and p.country_name = 'Suecia'
where t.name = 'FC Barcelona'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kylian Mbappé' and p.ovr = 91 and p.position = 'DC' and p.country_name = 'Francia'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jude Bellingham' and p.ovr = 90 and p.position = 'MCO' and p.country_name = 'Inglaterra'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Federico Valverde' and p.ovr = 89 and p.position = 'MC' and p.country_name = 'Uruguay'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Vinícius José de Oliveira Júnior' and p.ovr = 89 and p.position = 'EI' and p.country_name = 'Brasil'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Thibaut Courtois' and p.ovr = 89 and p.position = 'POR' and p.country_name = 'Bélgica'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Antonio Rüdiger' and p.ovr = 86 and p.position = 'DFC' and p.country_name = 'Alemania'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Trent Alexander-Arnold' and p.ovr = 86 and p.position = 'LD' and p.country_name = 'Inglaterra'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Daniel Carvajal Ramos' and p.ovr = 85 and p.position = 'LD' and p.country_name = 'España'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rodrygo Silva de Goes' and p.ovr = 85 and p.position = 'ED' and p.country_name = 'Brasil'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Aurélien Tchouaméni' and p.ovr = 84 and p.position = 'MCD' and p.country_name = 'Francia'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Éder Gabriel Militão' and p.ovr = 84 and p.position = 'DFC' and p.country_name = 'Brasil'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Eduardo Camavinga' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'Francia'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'David Alaba' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Austria'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Dean Huijsen' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'España'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Brahim Díaz' and p.ovr = 82 and p.position = 'MD' and p.country_name = 'Marruecos'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ferland Mendy' and p.ovr = 81 and p.position = 'LI' and p.country_name = 'Francia'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Andriy Lunin' and p.ovr = 81 and p.position = 'POR' and p.country_name = 'Ucrania'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Daniel Ceballos Fernández' and p.ovr = 81 and p.position = 'MC' and p.country_name = 'España'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Arda Güler' and p.ovr = 81 and p.position = 'MD' and p.country_name = 'Turquía'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Álvaro Fernández Carreras' and p.ovr = 80 and p.position = 'LI' and p.country_name = 'España'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Francisco José García Torres' and p.ovr = 79 and p.position = 'LI' and p.country_name = 'España'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Franco Mastantuono' and p.ovr = 77 and p.position = 'MCO' and p.country_name = 'Argentina'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Endrick Felipe Moreira de Sousa' and p.ovr = 77 and p.position = 'DC' and p.country_name = 'Brasil'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Raúl Asencio del Rosario' and p.ovr = 77 and p.position = 'DFC' and p.country_name = 'España'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Gonzalo García Torres' and p.ovr = 69 and p.position = 'DC' and p.country_name = 'España'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Francisco Javie González Pérez' and p.ovr = 63 and p.position = 'POR' and p.country_name = 'España'
where t.name = 'Real Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Bruno Miguel Borges Fernandes' and p.ovr = 87 and p.position = 'MCO' and p.country_name = 'Portugal'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Bryan Mbeumo' and p.ovr = 85 and p.position = 'ED' and p.country_name = 'Camerún'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Matheus Santos Carneiro da Cunha' and p.ovr = 83 and p.position = 'MCO' and p.country_name = 'Brasil'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Matthijs de Ligt' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Holanda'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Lisandro Martínez' and p.ovr = 81 and p.position = 'DFC' and p.country_name = 'Argentina'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'André Onana' and p.ovr = 80 and p.position = 'POR' and p.country_name = 'Camerún'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Noussair Mazraoui' and p.ovr = 80 and p.position = 'LD' and p.country_name = 'Marruecos'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Benjamin Šeško' and p.ovr = 80 and p.position = 'DC' and p.country_name = 'Eslovenia'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Carlos Henrique Venancio Casimiro' and p.ovr = 80 and p.position = 'MCD' and p.country_name = 'Brasil'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Harry Maguire' and p.ovr = 80 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'José Diogo Dalot Teixeira' and p.ovr = 79 and p.position = 'LD' and p.country_name = 'Portugal'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Luke Shaw' and p.ovr = 79 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Manuel Ugarte' and p.ovr = 79 and p.position = 'MCD' and p.country_name = 'Uruguay'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Amad Diallo' and p.ovr = 79 and p.position = 'MCO' and p.country_name = 'Costa de Marfil'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Senne Lammens' and p.ovr = 78 and p.position = 'POR' and p.country_name = 'Bélgica'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Leny Yoro' and p.ovr = 78 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kobbie Mainoo' and p.ovr = 77 and p.position = 'MC' and p.country_name = 'Inglaterra'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mason Mount' and p.ovr = 77 and p.position = 'MCO' and p.country_name = 'Inglaterra'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Joshua Zirkzee' and p.ovr = 77 and p.position = 'DC' and p.country_name = 'Holanda'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Tyrell Malacia' and p.ovr = 75 and p.position = 'LI' and p.country_name = 'Holanda'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Altay Bayındır' and p.ovr = 75 and p.position = 'POR' and p.country_name = 'Turquía'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Patrick Dorgu' and p.ovr = 74 and p.position = 'LI' and p.country_name = 'Dinamarca'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ayden Heaven' and p.ovr = 69 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Tom Heaton' and p.ovr = 67 and p.position = 'POR' and p.country_name = 'Inglaterra'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Chido Obi' and p.ovr = 65 and p.position = 'DC' and p.country_name = 'Dinamarca'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Tyler Fredricson' and p.ovr = 65 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Diego León' and p.ovr = 64 and p.position = 'LI' and p.country_name = 'Paraguay'
where t.name = 'Man Utd'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rodrigo Hernández Cascante' and p.ovr = 90 and p.position = 'MCD' and p.country_name = 'España'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Erling Haaland' and p.ovr = 90 and p.position = 'DC' and p.country_name = 'Noruega'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Gianluigi Donnarumma' and p.ovr = 89 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rúben Santos Gato Alves Dias' and p.ovr = 86 and p.position = 'DFC' and p.country_name = 'Portugal'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Tijjani Reijnders' and p.ovr = 86 and p.position = 'MC' and p.country_name = 'Holanda'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Phil Foden' and p.ovr = 85 and p.position = 'ED' and p.country_name = 'Inglaterra'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Joško Gvardiol' and p.ovr = 84 and p.position = 'LI' and p.country_name = 'Croacia'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Bernardo Mota Carvalho e Silva' and p.ovr = 84 and p.position = 'MC' and p.country_name = 'Portugal'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Omar Marmoush' and p.ovr = 84 and p.position = 'DC' and p.country_name = 'Egipto'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mateo Kovačić' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'Croacia'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nathan Aké' and p.ovr = 83 and p.position = 'DFC' and p.country_name = 'Holanda'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'John Stones' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Sávio Moreira de Oliveira' and p.ovr = 82 and p.position = 'ED' and p.country_name = 'Brasil'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rayan Aït-Nouri' and p.ovr = 81 and p.position = 'LI' and p.country_name = 'Argelia'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rayan Cherki' and p.ovr = 81 and p.position = 'ED' and p.country_name = 'Francia'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jérémy Doku' and p.ovr = 80 and p.position = 'EI' and p.country_name = 'Bélgica'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Matheus Luiz Nunes' and p.ovr = 79 and p.position = 'LD' and p.country_name = 'Portugal'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Stefan Ortega' and p.ovr = 79 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nicolás González Iglesias' and p.ovr = 79 and p.position = 'MCD' and p.country_name = 'España'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rico Lewis' and p.ovr = 77 and p.position = 'LD' and p.country_name = 'Inglaterra'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Abdukodir Khusanov' and p.ovr = 77 and p.position = 'DFC' and p.country_name = 'Uzbekistán'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'James Trafford' and p.ovr = 76 and p.position = 'POR' and p.country_name = 'Inglaterra'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kalvin Phillips' and p.ovr = 74 and p.position = 'MCD' and p.country_name = 'Inglaterra'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nico O''Reilly' and p.ovr = 73 and p.position = 'LI' and p.country_name = 'Inglaterra'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Oscar Bobb' and p.ovr = 72 and p.position = 'ED' and p.country_name = 'Noruega'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marcus Bettinelli' and p.ovr = 70 and p.position = 'POR' and p.country_name = 'Inglaterra'
where t.name = 'Manchester City'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Gabriel dos S. Magalhães' and p.ovr = 88 and p.position = 'DFC' and p.country_name = 'Brasil'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Bukayo Saka' and p.ovr = 88 and p.position = 'ED' and p.country_name = 'Inglaterra'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Declan Rice' and p.ovr = 87 and p.position = 'MCD' and p.country_name = 'Inglaterra'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'William Saliba' and p.ovr = 87 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Martin Ødegaard' and p.ovr = 87 and p.position = 'MC' and p.country_name = 'Noruega'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'David Raya Martin' and p.ovr = 87 and p.position = 'POR' and p.country_name = 'España'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Viktor Gyökeres' and p.ovr = 87 and p.position = 'DC' and p.country_name = 'Suecia'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mikel Merino Zazón' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'España'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Martín Zubimendi Ibáñez' and p.ovr = 83 and p.position = 'MCD' and p.country_name = 'España'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Eberechi Eze' and p.ovr = 83 and p.position = 'MCO' and p.country_name = 'Inglaterra'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Piero Hincapié' and p.ovr = 83 and p.position = 'DFC' and p.country_name = 'Ecuador'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Leandro Trossard' and p.ovr = 83 and p.position = 'EI' and p.country_name = 'Bélgica'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Benjamin White' and p.ovr = 83 and p.position = 'LD' and p.country_name = 'Inglaterra'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jurriën Timber' and p.ovr = 82 and p.position = 'LD' and p.country_name = 'Holanda'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kai Havertz' and p.ovr = 82 and p.position = 'DC' and p.country_name = 'Alemania'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Gabriel Teodoro Martinelli Silva' and p.ovr = 81 and p.position = 'EI' and p.country_name = 'Brasil'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Noni Madueke' and p.ovr = 80 and p.position = 'ED' and p.country_name = 'Inglaterra'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Gabriel Fernando de Jesus' and p.ovr = 80 and p.position = 'DC' and p.country_name = 'Brasil'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Christian Nørgaard' and p.ovr = 80 and p.position = 'MCD' and p.country_name = 'Dinamarca'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kepa Arrizabalaga' and p.ovr = 79 and p.position = 'POR' and p.country_name = 'España'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Myles Lewis-Skelly' and p.ovr = 78 and p.position = 'LI' and p.country_name = 'Inglaterra'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Riccardo Calafiori' and p.ovr = 78 and p.position = 'LI' and p.country_name = 'Italia'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Cristhian Mosquera Ibargüen' and p.ovr = 77 and p.position = 'DFC' and p.country_name = 'España'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ethan Nwaneri' and p.ovr = 76 and p.position = 'ED' and p.country_name = 'Inglaterra'
where t.name = 'Arsenal'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Xavi Simons' and p.ovr = 84 and p.position = 'MCO' and p.country_name = 'Holanda'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'James Maddison' and p.ovr = 84 and p.position = 'MC' and p.country_name = 'Inglaterra'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Dejan Kulusevski' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'Suecia'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'João Maria Palhinha Gonçalves' and p.ovr = 83 and p.position = 'MCD' and p.country_name = 'Portugal'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pedro Antonio Porro Sauceda' and p.ovr = 82 and p.position = 'LD' and p.country_name = 'España'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Guglielmo Vicario' and p.ovr = 82 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Micky van de Ven' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Holanda'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Cristian Romero' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Argentina'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Randal Kolo Muani' and p.ovr = 81 and p.position = 'DC' and p.country_name = 'Francia'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Destiny Udogie' and p.ovr = 80 and p.position = 'LI' and p.country_name = 'Italia'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mohammed Kudus' and p.ovr = 80 and p.position = 'ED' and p.country_name = 'Ghana'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rodrigo Bentancur' and p.ovr = 80 and p.position = 'MCD' and p.country_name = 'Uruguay'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Dominic Solanke' and p.ovr = 80 and p.position = 'DC' and p.country_name = 'Inglaterra'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pape Matar Sarr' and p.ovr = 79 and p.position = 'MC' and p.country_name = 'Senegal'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Brennan Johnson' and p.ovr = 79 and p.position = 'ED' and p.country_name = 'Gales'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kevin Danso' and p.ovr = 79 and p.position = 'DFC' and p.country_name = 'Austria'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Yves Bissouma' and p.ovr = 78 and p.position = 'MCD' and p.country_name = 'Malí'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Richarlison de Andrade' and p.ovr = 78 and p.position = 'DC' and p.country_name = 'Brasil'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Djed Spence' and p.ovr = 78 and p.position = 'LD' and p.country_name = 'Inglaterra'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Lucas Bergvall' and p.ovr = 77 and p.position = 'MC' and p.country_name = 'Suecia'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mathys Tel' and p.ovr = 77 and p.position = 'DC' and p.country_name = 'Francia'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Archie Gray' and p.ovr = 75 and p.position = 'MCD' and p.country_name = 'Inglaterra'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Antonín Kinský' and p.ovr = 75 and p.position = 'POR' and p.country_name = 'República Checa'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ben Davies' and p.ovr = 75 and p.position = 'DFC' and p.country_name = 'Gales'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Wilson Odobert' and p.ovr = 75 and p.position = 'EI' and p.country_name = 'Francia'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Radu Drăgușin' and p.ovr = 75 and p.position = 'DFC' and p.country_name = 'Rumanía'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kota Takai' and p.ovr = 72 and p.position = 'DFC' and p.country_name = 'Japón'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Brandon Austin' and p.ovr = 67 and p.position = 'POR' and p.country_name = 'Inglaterra'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Dane Scarlett' and p.ovr = 65 and p.position = 'DC' and p.country_name = 'Inglaterra'
where t.name = 'Spurs'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Gleison Bremer Silva Nascimento' and p.ovr = 85 and p.position = 'DFC' and p.country_name = 'Brasil'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Manuel Locatelli' and p.ovr = 84 and p.position = 'MCD' and p.country_name = 'Italia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Loïs Openda' and p.ovr = 83 and p.position = 'DC' and p.country_name = 'Bélgica'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jonathan David' and p.ovr = 82 and p.position = 'DC' and p.country_name = 'Canadá'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Dušan Vlahović' and p.ovr = 82 and p.position = 'DC' and p.country_name = 'Serbia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Khéphren Thuram' and p.ovr = 81 and p.position = 'MC' and p.country_name = 'Francia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Filip Kostić' and p.ovr = 81 and p.position = 'MI' and p.country_name = 'Serbia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Michele Di Gregorio' and p.ovr = 81 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Teun Koopmeiners' and p.ovr = 81 and p.position = 'MCO' and p.country_name = 'Holanda'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pierre Kalulu' and p.ovr = 80 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Federico Gatti' and p.ovr = 80 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Andrea Cambiaso' and p.ovr = 79 and p.position = 'LI' and p.country_name = 'Italia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kenan Yıldız' and p.ovr = 79 and p.position = 'MCO' and p.country_name = 'Turquía'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Edon Zhegrova' and p.ovr = 79 and p.position = 'MD' and p.country_name = 'Kosovo'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Francisco F. da Conceição' and p.ovr = 79 and p.position = 'MD' and p.country_name = 'Portugal'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Arkadiusz Milik' and p.ovr = 79 and p.position = 'DC' and p.country_name = 'Polonia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Weston McKennie' and p.ovr = 78 and p.position = 'MC' and p.country_name = 'Estados Unidos'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mattia Perin' and p.ovr = 78 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'João Mário Neto Lopes' and p.ovr = 77 and p.position = 'LD' and p.country_name = 'Portugal'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Daniele Rugani' and p.ovr = 75 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Fabio Miretti' and p.ovr = 74 and p.position = 'MC' and p.country_name = 'Italia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Lloyd Kelly' and p.ovr = 74 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Juan David Cabal' and p.ovr = 74 and p.position = 'LI' and p.country_name = 'Colombia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Carlo Pinsoglio' and p.ovr = 69 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jonas Rouhi' and p.ovr = 66 and p.position = 'LI' and p.country_name = 'Suecia'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Vasilije Adžić' and p.ovr = 62 and p.position = 'MCO' and p.country_name = 'Montenegro'
where t.name = 'Juventus'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mike Maignan' and p.ovr = 87 and p.position = 'POR' and p.country_name = 'Francia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Christian Pulisic' and p.ovr = 84 and p.position = 'ED' and p.country_name = 'Estados Unidos'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rafael da Conceição Leão' and p.ovr = 84 and p.position = 'EI' and p.country_name = 'Portugal'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Adrien Rabiot' and p.ovr = 83 and p.position = 'MCO' and p.country_name = 'Francia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Luka Modrić' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'Croacia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Youssouf Fofana' and p.ovr = 81 and p.position = 'MCD' and p.country_name = 'Francia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Christopher Nkunku' and p.ovr = 81 and p.position = 'MCO' and p.country_name = 'Francia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Fikayo Tomori' and p.ovr = 81 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ruben Loftus-Cheek' and p.ovr = 80 and p.position = 'MC' and p.country_name = 'Inglaterra'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pervis Estupiñán' and p.ovr = 79 and p.position = 'LI' and p.country_name = 'Ecuador'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alexis Saelemaekers' and p.ovr = 79 and p.position = 'MD' and p.country_name = 'Bélgica'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Santiago Giménez' and p.ovr = 79 and p.position = 'DC' and p.country_name = 'México'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Yacine Adli' and p.ovr = 78 and p.position = 'MCD' and p.country_name = 'Francia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Samuele Ricci' and p.ovr = 78 and p.position = 'MCD' and p.country_name = 'Italia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pietro Terracciano' and p.ovr = 78 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Matteo Gabbia' and p.ovr = 78 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ardon Jashari' and p.ovr = 77 and p.position = 'MCD' and p.country_name = 'Suiza'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Strahinja Pavlović' and p.ovr = 76 and p.position = 'DFC' and p.country_name = 'Serbia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Koni De Winter' and p.ovr = 74 and p.position = 'DFC' and p.country_name = 'Bélgica'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Zachary Athekame' and p.ovr = 65 and p.position = 'LD' and p.country_name = 'Suiza'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'David Odogu' and p.ovr = 65 and p.position = 'DFC' and p.country_name = 'Alemania'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Davide Bartesaghi' and p.ovr = 62 and p.position = 'LI' and p.country_name = 'Italia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Lorenzo Torriani' and p.ovr = 61 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'Milano FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Lautaro Martínez' and p.ovr = 88 and p.position = 'DC' and p.country_name = 'Argentina'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alessandro Bastoni' and p.ovr = 87 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Yann Sommer' and p.ovr = 87 and p.position = 'POR' and p.country_name = 'Suiza'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nicolò Barella' and p.ovr = 87 and p.position = 'MC' and p.country_name = 'Italia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Hakan Çalhanoğlu' and p.ovr = 86 and p.position = 'MCD' and p.country_name = 'Turquía'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Federico Dimarco' and p.ovr = 85 and p.position = 'LI' and p.country_name = 'Italia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marcus Thuram' and p.ovr = 85 and p.position = 'DC' and p.country_name = 'Francia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Denzel Dumfries' and p.ovr = 84 and p.position = 'LD' and p.country_name = 'Holanda'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Francesco Acerbi' and p.ovr = 84 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Stefan de Vrij' and p.ovr = 84 and p.position = 'DFC' and p.country_name = 'Holanda'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Henrikh Mkhitaryan' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'Armenia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Manuel Akanji' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Suiza'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Davide Frattesi' and p.ovr = 81 and p.position = 'MC' and p.country_name = 'Italia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Carlos Augusto Zopolato Neves' and p.ovr = 81 and p.position = 'LI' and p.country_name = 'Brasil'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Matteo Darmian' and p.ovr = 81 and p.position = 'LD' and p.country_name = 'Italia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Piotr Zieliński' and p.ovr = 80 and p.position = 'MC' and p.country_name = 'Polonia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Luis Henrique Tomaz de Lima' and p.ovr = 78 and p.position = 'MD' and p.country_name = 'Brasil'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Yann Aurel Bisseck' and p.ovr = 76 and p.position = 'DFC' and p.country_name = 'Alemania'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Yoan Bonny' and p.ovr = 76 and p.position = 'DC' and p.country_name = 'Francia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Andy Diouf' and p.ovr = 75 and p.position = 'MC' and p.country_name = 'Francia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Josep Martínez Riera' and p.ovr = 75 and p.position = 'POR' and p.country_name = 'España'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Petar Sučić' and p.ovr = 74 and p.position = 'MC' and p.country_name = 'Croacia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Francesco Pio Esposito' and p.ovr = 71 and p.position = 'DC' and p.country_name = 'Italia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Raffaele Di Gennaro' and p.ovr = 68 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Tomás Palacios' and p.ovr = 67 and p.position = 'DFC' and p.country_name = 'Argentina'
where t.name = 'Lombardia FC'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Kevin De Bruyne' and p.ovr = 87 and p.position = 'MC' and p.country_name = 'Bélgica'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Scott McTominay' and p.ovr = 85 and p.position = 'MC' and p.country_name = 'Escocia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Romelu Lukaku' and p.ovr = 84 and p.position = 'DC' and p.country_name = 'Bélgica'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Giovanni Di Lorenzo' and p.ovr = 83 and p.position = 'LD' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Stanislav Lobotka' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'Eslovaquia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Amir Rrahmani' and p.ovr = 83 and p.position = 'DFC' and p.country_name = 'Kosovo'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'André-Franck Zambo Anguissa' and p.ovr = 82 and p.position = 'MC' and p.country_name = 'Camerún'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alex Meret' and p.ovr = 82 and p.position = 'POR' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alessandro Buongiorno' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Miguel Gutiérrez Ortega' and p.ovr = 81 and p.position = 'LI' and p.country_name = 'España'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Matteo Politano' and p.ovr = 81 and p.position = 'ED' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'David Neres Campos' and p.ovr = 81 and p.position = 'EI' and p.country_name = 'Brasil'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Noa Lang' and p.ovr = 80 and p.position = 'EI' and p.country_name = 'Holanda'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Vanja Milinković-Savić' and p.ovr = 79 and p.position = 'POR' and p.country_name = 'Serbia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Leonardo Spinazzola' and p.ovr = 78 and p.position = 'LI' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mathías Olivera' and p.ovr = 78 and p.position = 'LI' and p.country_name = 'Uruguay'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Sam Beukema' and p.ovr = 78 and p.position = 'DFC' and p.country_name = 'Holanda'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Eljif Elmas' and p.ovr = 77 and p.position = 'MI' and p.country_name = 'Macedonia del Norte'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Rasmus Højlund' and p.ovr = 76 and p.position = 'DC' and p.country_name = 'Dinamarca'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Lorenzo Lucca' and p.ovr = 76 and p.position = 'DC' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Billy Gilmour' and p.ovr = 74 and p.position = 'MC' and p.country_name = 'Escocia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Juan Guilherme Nunes Jesus' and p.ovr = 74 and p.position = 'DFC' and p.country_name = 'Brasil'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pasquale Mazzocchi' and p.ovr = 72 and p.position = 'LD' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Luca Marianucci' and p.ovr = 68 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nikita Contini' and p.ovr = 67 and p.position = 'POR' and p.country_name = 'Ucrania'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Giuseppe Ambrosino' and p.ovr = 67 and p.position = 'DC' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Antonio Vergara' and p.ovr = 65 and p.position = 'ED' and p.country_name = 'Italia'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Coli Saco' and p.ovr = 61 and p.position = 'MC' and p.country_name = 'Malí'
where t.name = 'SSC Napoli'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Joshua Kimmich' and p.ovr = 89 and p.position = 'MCD' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Harry Kane' and p.ovr = 89 and p.position = 'DC' and p.country_name = 'Inglaterra'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jamal Musiala' and p.ovr = 88 and p.position = 'MCO' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jonathan Tah' and p.ovr = 87 and p.position = 'DFC' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Michael Olise' and p.ovr = 86 and p.position = 'MD' and p.country_name = 'Francia'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Luis Díaz' and p.ovr = 85 and p.position = 'MI' and p.country_name = 'Colombia'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Dayot Upamecano' and p.ovr = 85 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alphonso Davies' and p.ovr = 84 and p.position = 'LI' and p.country_name = 'Canadá'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Manuel Neuer' and p.ovr = 84 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Leon Goretzka' and p.ovr = 82 and p.position = 'MC' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Konrad Laimer' and p.ovr = 82 and p.position = 'LD' and p.country_name = 'Austria'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Serge Gnabry' and p.ovr = 82 and p.position = 'MI' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Min Jae Kim' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'República de Corea'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Raphaël Guerreiro' and p.ovr = 80 and p.position = 'LI' and p.country_name = 'Portugal'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nicolas Jackson' and p.ovr = 80 and p.position = 'DC' and p.country_name = 'Senegal'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Aleksandar Pavlović' and p.ovr = 79 and p.position = 'MCD' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Hiroki Ito' and p.ovr = 78 and p.position = 'DFC' and p.country_name = 'Japón'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Josip Stanišić' and p.ovr = 78 and p.position = 'DFC' and p.country_name = 'Croacia'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Sacha Boey' and p.ovr = 77 and p.position = 'LD' and p.country_name = 'Francia'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Tom Bischof' and p.ovr = 76 and p.position = 'MC' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jonas Urbig' and p.ovr = 74 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Sven Ulreich' and p.ovr = 73 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Lennart Karl' and p.ovr = 63 and p.position = 'MCO' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'David Santos Daiber' and p.ovr = 59 and p.position = 'MCD' and p.country_name = 'Portugal'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Leon Klanac' and p.ovr = 56 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'FC Bayern München'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Patrik Schick' and p.ovr = 85 and p.position = 'DC' and p.country_name = 'República Checa'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alejandro Grimaldo García' and p.ovr = 84 and p.position = 'MI' and p.country_name = 'España'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Exequiel Palacios' and p.ovr = 84 and p.position = 'MC' and p.country_name = 'Argentina'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Aleix García Serrano' and p.ovr = 83 and p.position = 'MC' and p.country_name = 'España'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Malik Tillman' and p.ovr = 82 and p.position = 'MCO' and p.country_name = 'Estados Unidos'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Robert Andrich' and p.ovr = 81 and p.position = 'MCD' and p.country_name = 'Alemania'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Edmond Tapsoba' and p.ovr = 81 and p.position = 'DFC' and p.country_name = 'Burkina Faso'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Martin Terrier' and p.ovr = 79 and p.position = 'DC' and p.country_name = 'Francia'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jonas Hofmann' and p.ovr = 78 and p.position = 'MCO' and p.country_name = 'Alemania'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Mark Flekken' and p.ovr = 78 and p.position = 'POR' and p.country_name = 'Holanda'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nathan Tella' and p.ovr = 78 and p.position = 'MD' and p.country_name = 'Nigeria'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Loïc Badé' and p.ovr = 78 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Eliesse Ben Seghir' and p.ovr = 76 and p.position = 'MI' and p.country_name = 'Marruecos'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ezequiel Fernández' and p.ovr = 75 and p.position = 'MCD' and p.country_name = 'Argentina'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jarell Quansah' and p.ovr = 75 and p.position = 'DFC' and p.country_name = 'Inglaterra'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Claudio Echeverri' and p.ovr = 74 and p.position = 'MCO' and p.country_name = 'Argentina'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Janis Blaswich' and p.ovr = 73 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ibrahim Maza' and p.ovr = 71 and p.position = 'MCO' and p.country_name = 'Argelia'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Arthur Augusto de Matos Soares' and p.ovr = 71 and p.position = 'LD' and p.country_name = 'Brasil'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ernest Poku' and p.ovr = 70 and p.position = 'MD' and p.country_name = 'Holanda'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jeanuël Belocian' and p.ovr = 70 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Christian Kofane' and p.ovr = 68 and p.position = 'DC' and p.country_name = 'Camerún'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Niklas Lomb' and p.ovr = 66 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Axel Tape' and p.ovr = 65 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alejo Sarco' and p.ovr = 64 and p.position = 'DC' and p.country_name = 'Argentina'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jeremiah Mensah' and p.ovr = 61 and p.position = 'MC' and p.country_name = 'Alemania'
where t.name = 'Leverkusen'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Serhou Guirassy' and p.ovr = 87 and p.position = 'DC' and p.country_name = 'Guinea'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Gregor Kobel' and p.ovr = 86 and p.position = 'POR' and p.country_name = 'Suiza'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nico Schlotterbeck' and p.ovr = 85 and p.position = 'DFC' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Julian Brandt' and p.ovr = 83 and p.position = 'MCO' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Felix Nmecha' and p.ovr = 82 and p.position = 'MCD' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Emre Can' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Waldemar Anton' and p.ovr = 82 and p.position = 'DFC' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Karim Adeyemi' and p.ovr = 81 and p.position = 'MD' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Niklas Süle' and p.ovr = 81 and p.position = 'DFC' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marcel Sabitzer' and p.ovr = 80 and p.position = 'MCD' and p.country_name = 'Austria'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pascal Groß' and p.ovr = 80 and p.position = 'MCD' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Ramy Bensebaini' and p.ovr = 79 and p.position = 'LI' and p.country_name = 'Argelia'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Julian Ryerson' and p.ovr = 79 and p.position = 'LD' and p.country_name = 'Noruega'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Maximilian Beier' and p.ovr = 79 and p.position = 'DC' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Fábio Daniel Soares Silva' and p.ovr = 79 and p.position = 'DC' and p.country_name = 'Portugal'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Daniel Svensson' and p.ovr = 77 and p.position = 'LI' and p.country_name = 'Suecia'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Yan Bueno Couto' and p.ovr = 77 and p.position = 'LD' and p.country_name = 'Brasil'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Carney Chukwuemeka' and p.ovr = 76 and p.position = 'MCO' and p.country_name = 'Inglaterra'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Salih Özcan' and p.ovr = 75 and p.position = 'MCD' and p.country_name = 'Turquía'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alexander Meyer' and p.ovr = 75 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jobe Bellingham' and p.ovr = 74 and p.position = 'MC' and p.country_name = 'Inglaterra'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Julien Duranville' and p.ovr = 72 and p.position = 'MD' and p.country_name = 'Bélgica'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Patrick Drewes' and p.ovr = 71 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Aaron Anselmino' and p.ovr = 70 and p.position = 'DFC' and p.country_name = 'Argentina'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Cole Campbell' and p.ovr = 67 and p.position = 'MD' and p.country_name = 'Estados Unidos'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Almugera Kabar' and p.ovr = 64 and p.position = 'LI' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Silas Ostrzinski' and p.ovr = 63 and p.position = 'POR' and p.country_name = 'Alemania'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Filippo Mane' and p.ovr = 62 and p.position = 'DFC' and p.country_name = 'Italia'
where t.name = 'Borussia Dortmund'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jan Oblak' and p.ovr = 88 and p.position = 'POR' and p.country_name = 'Eslovenia'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Julián Alvarez' and p.ovr = 87 and p.position = 'DC' and p.country_name = 'Argentina'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Antoine Griezmann' and p.ovr = 85 and p.position = 'DC' and p.country_name = 'Francia'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marcos Llorente Moreno' and p.ovr = 84 and p.position = 'LD' and p.country_name = 'España'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alejandro Baena Rodríguez' and p.ovr = 84 and p.position = 'MI' and p.country_name = 'España'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Alexander Sørloth' and p.ovr = 84 and p.position = 'DC' and p.country_name = 'Noruega'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Dávid Hancko' and p.ovr = 83 and p.position = 'DFC' and p.country_name = 'Eslovaquia'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'José María Giménez' and p.ovr = 83 and p.position = 'DFC' and p.country_name = 'Uruguay'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Robin Le Normand' and p.ovr = 83 and p.position = 'DFC' and p.country_name = 'España'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Pablo Barrios Rivas' and p.ovr = 82 and p.position = 'MC' and p.country_name = 'España'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Conor Gallagher' and p.ovr = 81 and p.position = 'MC' and p.country_name = 'Inglaterra'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'João Lucas de Souza Cardoso' and p.ovr = 81 and p.position = 'MCD' and p.country_name = 'Estados Unidos'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Jorge Resurrección' and p.ovr = 81 and p.position = 'MC' and p.country_name = 'España'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Giuliano Simeone' and p.ovr = 81 and p.position = 'MD' and p.country_name = 'Argentina'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Javier Galán Gil' and p.ovr = 80 and p.position = 'LI' and p.country_name = 'España'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Clément Lenglet' and p.ovr = 80 and p.position = 'DFC' and p.country_name = 'Francia'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nahuel Molina' and p.ovr = 79 and p.position = 'LD' and p.country_name = 'Argentina'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Juan Musso' and p.ovr = 79 and p.position = 'POR' and p.country_name = 'Argentina'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Thiago Almada' and p.ovr = 79 and p.position = 'MCO' and p.country_name = 'Argentina'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Nico Gonzalez' and p.ovr = 78 and p.position = 'MD' and p.country_name = 'Argentina'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Giacomo Raspadori' and p.ovr = 78 and p.position = 'DC' and p.country_name = 'Italia'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Matteo Ruggeri' and p.ovr = 75 and p.position = 'MI' and p.country_name = 'Italia'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Marc Pubill Pagès' and p.ovr = 73 and p.position = 'LD' and p.country_name = 'España'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
insert into team_players (team_id, player_id)
select t.id, p.id from teams t join players p on p.name = 'Carlos Martín Domínguez' and p.ovr = 70 and p.position = 'DC' and p.country_name = 'España'
where t.name = 'Atlético de Madrid'
on conflict do nothing;
commit;